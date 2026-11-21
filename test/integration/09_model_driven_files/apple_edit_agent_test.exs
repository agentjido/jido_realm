Code.require_file("apple_edit_guest.exs", __DIR__)
Code.require_file("apple_edit_tools.exs", __DIR__)

defmodule Jido.Realm.Integration.AppleEditAgentTest do
  use ExUnit.Case

  alias Jido.Realm
  alias Jido.Realm.AppleEdit.{EditAgent, Guest}
  alias Jido.Realm.{Coding, Placement, Plugin, Profile, Session}

  @fixture Path.join(__DIR__, "apple_edit_fixture")
  @model_url "http://127.0.0.1:1234/v1"
  @turn_timeout 230_000
  @intro "Jido Realm gives agents a workspace."
  @rounds [
    {1,
     """
     Add a short introductory paragraph to the home page with the exact text
     "Jido Realm gives agents a workspace." Keep the original greeting.
     Run the project checks before you finish.
     """},
    {2,
     """
     Add GET /api/realm. It must return HTTP 200 JSON with exactly {"status":"ready"}.
     Add a new ExUnit test file for this endpoint. Preserve the home page and run the
     project checks after your final edit.
     """},
    {3,
     """
     First run this round's acceptance checks before editing and inspect the failure.
     Make unknown routes return a Phoenix 404 page with the text "Page not found"
     and a "Back to home" link using href="/". Preserve the API and home page.
     Update the existing Phoenix error renderer. Use static HTML for the page. The check name is "acceptance-3".
     Run the same acceptance checks after your final edit.
     """}
  ]

  @tag :docker
  @tag timeout: 240_000
  test "a coding job checks and serves a Docker Realm", do: deterministic(:docker)

  @tag :apple_container
  @tag timeout: 240_000
  test "a coding job checks and serves an Apple Container Realm",
    do: deterministic(:apple_container)

  defp deterministic(engine) do
    with_realm("deterministic-#{engine}", engine, fn guest, context, _lease ->
      baseline(guest)
      path = "lib/realm_demo/page.ex"
      assert {:ok, %{revision: revision}} = Coding.Read.run(%{realm: :work, path: path}, context)

      assert {:ok, %{paths: [^path]}} =
               Coding.Glob.run(%{realm: :work, pattern: "**/page.ex"}, context)

      assert {:ok, %{matches: [%{path: ^path, line: _, text: text}]}} =
               Coding.Grep.run(
                 %{realm: :work, native: true, regex: true, path: "lib", query: "Hello, .+!"},
                 context
               )

      assert text =~ "Hello, world!"

      assert {:ok, %{matches: [%{path: ^path}]}} =
               Coding.Grep.run(
                 %{realm: :work, native: true, path: "lib", query: "Hello, world!"},
                 context
               )

      assert {:ok, %{matches: [_], truncated: true}} =
               Coding.Grep.run(%{realm: :work, native: true, query: "Hello", limit: 1}, context)

      assert {:error, _} =
               Coding.Grep.run(
                 %{realm: :work, native: true, path: "../", query: "Hello"},
                 context
               )

      green = Guest.check(guest, "project")
      assert_pass(green)

      patch = %{
        realm: :work,
        path: path,
        revision: revision,
        old_text: "</h1>",
        new_text: "</h1><p>#{@intro}</p>"
      }

      assert {:ok, %{revision: committed}} = Coding.Edit.run(patch, context)
      assert committed != revision
      assert {:error, %{message: conflict}} = Coding.Edit.run(patch, context)
      assert conflict =~ "conflict"
      assert {:error, %{message: denied}} = Coding.Edit.run(%{patch | path: "mix.lock"}, context)
      assert denied =~ "permission_denied"

      assert {:error, :stale_source} =
               Realm.start_checked_preview(context, :work, "app", green.source_ref)

      assert {:error, :stale_source} =
               Realm.coding_run(context, :work, :check, %{
                 name: "project",
                 source_ref: green.source_ref
               })

      Guest.round(guest, 1)
      assert_pass(Guest.check(guest, "project"))
      assert_pass(Guest.check(guest, "acceptance"))
      ensure_replay(guest, context)

      assert {:ok, %{status: :test_failed, exit_code: 2, output: output}} =
               Coding.RunCheck.run(%{realm: :work, name: "acceptance-3"}, context)

      assert output =~ "a missing route has a custom 404 page"

      assert {:ok, %{content: lock}} = Realm.file(context, :work, :read, "mix.lock")
      assert {:ok, _} = Realm.file(context, :work, :edit, "mix.lock", lock <> "\n# changed lock")
      assert %{status: :setup_failed, exit_code: 78} = Guest.check(guest, "project")
      assert {:ok, _} = Realm.file(context, :work, :edit, "mix.lock", lock)

      assert %{status: :resource_limit, truncated: true, output: bounded} =
               Guest.shell(guest, "bounded_output", "yes realm")

      assert byte_size(bounded) <= Jido.Realm.Runner.output_limit()

      assert {:error, {:service_exited, _}} =
               Realm.start_checked_preview(
                 context,
                 :work,
                 "failing",
                 Guest.check(guest, "project").source_ref
               )

      observe(guest, 1, snapshot(guest, "round-1"))

      Guest.preview(guest, fn url, _id, key ->
        assert {:ok, %{status: 404}} = Guest.request(url)

        assert {:ok, _} =
                 Coding.Edit.run(
                   %{patch | revision: committed, old_text: @intro, new_text: "new source"},
                   context
                 )

        assert {:ok, %{status: 200, body: body}} = Guest.request(url, key)
        assert body =~ @intro
        refute body =~ "new source"
      end)
    end)
  end

  defp ensure_replay(guest, context) do
    id = "stable-timeout"
    timeout = %{command: "sleep 10", timeout_ms: 350}

    assert {:ok, %{id: ^id, status: :timed_out} = terminal} =
             Realm.coding_run(context, :work, :bash, timeout, request_id: id)

    assert {:ok, ^terminal} = Realm.run_status(context, :work, id)
    assert {:ok, ^terminal} = Realm.coding_run(context, :work, :bash, timeout, request_id: id)

    assert {:error, :request_conflict} =
             Realm.coding_run(context, :work, :bash, %{timeout | command: "false"},
               request_id: id
             )

    record(guest, "timeout-replay", terminal)
  end

  @tag :lmstudio
  @tag timeout: 1_350_000
  test "LM Studio edits one Apple-backed Realm in three successive rounds" do
    with_realm("live", :apple_container, fn guest, context, lease ->
      model = System.get_env("JIDO_REALM_LMSTUDIO_MODEL", "qwen3.8-27b-realm")
      instance = __MODULE__.LMStudio
      start_supervised!({Jido, name: instance})
      binding = [session: session(context), grants: [:read, :write, :run]]

      assert {:ok, agent} =
               Jido.start_agent(instance, EditAgent,
                 id: guest.id,
                 turn_timeout: @turn_timeout,
                 plugin_runtime_options: [{Plugin, bindings: %{work: binding}}]
               )

      assert :ok = Jido.AgentServer.await_ready(agent)

      record(guest, "run", %{
        realm_id: lease.id,
        agent_id: guest.id,
        model: model,
        endpoint: @model_url
      })

      probe =
        turn(agent, model, guest, "model-preflight", """
        Use read with realm "work" and path "mix.exs" once. Then report the exact OTP application name from the tool result.
        """)

      assert [%{tool_name: "read", status: :ok, input: %{"path" => "mix.exs"}}] =
               probe.tool_attempts

      assert hd(probe.tool_attempts).output["content"] =~ "app: :realm_edit_demo"
      baseline(guest)
      initial = snapshot(guest, "baseline")
      observe(guest, 0, initial)

      Enum.reduce(@rounds, {"baseline", initial}, fn {round, prompt}, {previous_name, previous} ->
        edit_round(agent, model, guest, round, prompt, previous_name, previous)
      end)
    end)
  end

  defp with_realm(mode, engine, fun) do
    id =
      System.get_env("JIDO_REALM_APPLE_EDIT_ID") ||
        Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)

    assert Regex.match?(~r/\A[a-z0-9-]{1,40}\z/, id)
    scratch = Path.join(System.tmp_dir!(), "jido-realm-apple-edit-#{id}")
    File.mkdir!(scratch)
    File.write!(Path.join(scratch, "host-only"), "sentinel")
    parent = Path.expand("tmp/apple-edit-evidence")
    File.mkdir_p!(parent)
    evidence = Path.join(parent, id)
    File.mkdir!(evidence)
    IO.puts("Apple Realm #{mode} evidence: #{evidence}")

    on_exit(fn ->
      if File.exists?(Path.join(evidence, "closed.json")), do: File.rm_rf!(scratch)
    end)

    guest = Guest.new(scratch, evidence, id, engine)

    assert {:ok, realm_session} =
             Session.start_link(
               [
                 owner: self(),
                 provider: {Placement, {:local, Guest.workspace(guest)}}
               ] ++ Guest.options(guest)
             )

    assert {:ok, profile} = Profile.resolve(Jido.Realm.AppleEdit.Profile)
    context = host_context(realm_session, profile)
    guest = Map.merge(guest, %{context: context, session: realm_session})
    assert {:ok, lease} = Realm.open(context, :work)

    try do
      assert {:ok, %{entries: []}} = Realm.file(context, :work, :list, ".")
      seed(context)
      fun.(guest, context, lease)
    after
      Guest.cleanup!(guest)
      close = Realm.close(context, :work)
      assert close == :ok or match?({:ok, _}, close)
      assert {:error, :enoent} = File.stat(Guest.workspace(guest))

      record(guest, "closed", %{
        realm_id: lease.id,
        guest_resources_absent: true,
        workspace_released: true
      })

      Agent.stop(guest.state)
    end
  end

  defp host_context(session, profile) do
    %{
      plugin_inputs: %{
        Plugin => %{
          runtime: %{bindings: %{"work" => %{target: {:session, session, profile}, grants: :all}}}
        }
      }
    }
  end

  defp session(%{plugin_inputs: %{Plugin => %{runtime: runtime}}}) do
    {:ok, %{target: {:session, session, _}}} = Plugin.binding(runtime, :work)
    session
  end

  defp seed(context) do
    for directory <- ["lib", "lib/realm_demo", "test"] do
      assert {:ok, _} = Realm.file(context, :work, :mkdir, directory)
    end

    for source <- Path.wildcard(Path.join(@fixture, "**/*.seed")),
        path = source |> Path.relative_to(@fixture) |> String.trim_trailing(".seed"),
        not String.starts_with?(path, "acceptance/") do
      assert {:ok, _} = Realm.file(context, :work, :create, path, File.read!(source))
    end
  end

  defp baseline(guest) do
    lockfile = Path.join(Guest.workspace(guest), "mix.lock")
    lock = File.read!(lockfile)
    assert_pass(Guest.prepare(guest))
    assert File.read!(lockfile) == lock
    assert_pass(Guest.mount_check(guest))
    assert_pass(Guest.check(guest, "project"))
  end

  defp edit_round(agent, model, guest, round, prompt, previous_name, previous) do
    Guest.round(guest, round)
    name = "round-#{round}"
    result = turn(agent, model, guest, name, prompt)
    verify_tools(result.tool_attempts, round)
    current = snapshot(guest, name)
    assert current != previous
    diff(guest, previous_name, name)
    assert_pass(Guest.check(guest, "project"))
    assert_pass(Guest.check(guest, "acceptance"))
    observe(guest, round, current)
    {name, current}
  rescue
    error ->
      failed = "round-#{round}-failed"
      if snapshot(guest, failed) != previous, do: diff(guest, previous_name, failed)
      reraise error, __STACKTRACE__
  end

  defp turn(agent, model, guest, label, prompt) do
    signal =
      EditAgent.request_signal!(%{
        model: "lmstudio:" <> model,
        options: %{
          base_url: @model_url,
          reasoning_effort: :none,
          max_tokens: 1_400,
          temperature: 0.1,
          receive_timeout: 60_000,
          max_retries: 0
        },
        input: prompt
      })

    started = System.monotonic_time(:millisecond)
    request = Jido.AgentServer.call(agent, signal, @turn_timeout + 5_000)

    case request do
      {:ok, %{reply: %{data: %{tool_attempts: _} = result}}} ->
        evidence = Map.take(result, [:status, :reason, :text, :model_calls, :tool_attempts])

        evidence =
          Map.merge(evidence, %{
            prompt: prompt,
            duration_ms: System.monotonic_time(:millisecond) - started
          })

        record(guest, "#{label}-tools", evidence)
        assert result.status == :completed, inspect({result.status, result.reason})
        IO.puts("#{label}: #{length(result.tool_attempts)} actual tool calls")
        result

      other ->
        record(guest, "#{label}-failure", %{result: inspect(other, limit: 50)})
        flunk("Jido returned no completed tool trace for #{label}: #{inspect(other, limit: 12)}")
    end
  end

  defp verify_tools(attempts, round) do
    {before_edits, edits} = Enum.split_while(attempts, &(not mutation?(&1)))
    assert [%{input: %{"path" => path}} | _] = edits
    assert Enum.any?(before_edits, &(&1.status == :ok and &1.tool_name == "read"))

    last_edit = attempts |> Enum.reverse() |> Enum.find(&mutation?/1)

    assert Enum.any?(attempts, fn call ->
             call.tool_round > last_edit.tool_round and passed_check?(call)
           end),
           "No passing guest check followed #{path} and the final edits"

    if round == 2 do
      assert Enum.any?(edits, fn call ->
               call.status == :ok and call.tool_name == "write" and
                 String.starts_with?(call.input["path"], "test/")
             end)
    end

    if round == 3 do
      assert Enum.any?(before_edits, fn call ->
               match?(
                 %{
                   tool_name: "run_check",
                   input: %{"name" => "acceptance-3"},
                   output: %{"exit_code" => 2}
                 },
                 call
               ) and
                 call.output["output"] =~ "a missing route has a custom 404 page"
             end)

      assert Enum.any?(attempts, fn call ->
               call.tool_round > last_edit.tool_round and passed_check?(call) and
                 call.input["name"] == "acceptance-3"
             end)
    end
  end

  defp mutation?(call),
    do: call.status == :ok and call.tool_name in ["edit", "write"]

  defp passed_check?(call) do
    match?(%{tool_name: "run_check", status: :ok, output: %{"exit_code" => 0}}, call)
  end

  defp snapshot(guest, label) do
    source = Guest.workspace(guest)
    saved = Path.join([guest.evidence, "source", label])

    files = source |> Path.join("{lib,test}/**/*.{ex,exs}") |> Path.wildcard()
    paths = ["mix.exs", "mix.lock"] ++ Enum.map(files, &Path.relative_to(&1, source))

    manifest =
      Map.new(paths, fn path ->
        content = File.read!(Path.join(source, path))
        destination = Path.join(saved, path)
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, content)
        {path, Base.encode16(:crypto.hash(:sha256, content), case: :lower)}
      end)

    record(guest, "#{label}-manifest", manifest)
    manifest
  end

  defp diff(guest, previous, current) do
    {patch, 1} =
      System.cmd("git", ["diff", "--no-index", "--no-ext-diff", "--no-color", previous, current],
        cd: Path.join(guest.evidence, "source")
      )

    File.write!(Path.join(guest.evidence, "#{current}.diff"), patch)
  end

  defp observe(guest, round, manifest) do
    Guest.preview(guest, fn url, service, key ->
      assert {:ok, %{status: 200, body: home}} = Guest.request(url, key)
      assert home =~ "<h1>Hello, world!</h1>"
      if round >= 1, do: assert(home =~ @intro)

      if round == 0 do
        assert {:ok, %{status: 404, body: "Not found"}} =
                 Guest.request(url <> "missing-realm-page", key)
      end

      if round >= 2 do
        assert {:ok, %{status: 200, body: body, headers: headers}} =
                 Guest.request(url <> "api/realm", key)

        assert Enum.any?(headers["content-type"], &String.starts_with?(&1, "application/json"))
        assert JSON.decode!(body) == %{"status" => "ready"}
      end

      if round >= 3 do
        assert {:ok, %{status: 404, body: missing}} =
                 Guest.request(url <> "missing-realm-page", key)

        assert missing =~ "Page not found"
        assert missing =~ ~s(href="/")
        assert missing =~ "Back to home"
      end

      record(guest, "preview-#{round}", %{
        round: round,
        url: url,
        service: service,
        browser_url: url <> "?viewer=" <> key,
        manifest: manifest
      })

      IO.puts("Preview #{round}: #{url}")

      if System.get_env("JIDO_REALM_APPLE_EDIT_BROWSER") == "1" do
        await_browser(guest, round, url, System.monotonic_time(:millisecond) + 120_000)
      end
    end)
  end

  defp await_browser(guest, round, url, deadline) do
    marker = Path.join(guest.evidence, "browser-#{round}.json")

    case File.read(marker) do
      {:ok, content} ->
        assert %{"url" => ^url, "verified" => true} = JSON.decode!(content)

      {:error, :enoent} ->
        assert System.monotonic_time(:millisecond) < deadline, "Browser proof timed out at #{url}"
        Process.sleep(200)
        await_browser(guest, round, url, deadline)
    end
  end

  defp record(guest, name, data) do
    File.write!(
      Path.join(guest.evidence, "#{name}.json"),
      Jason.encode_to_iodata!(data, pretty: true)
    )
  end

  defp assert_pass(result), do: assert(result.exit_code == 0, result.output)
end
