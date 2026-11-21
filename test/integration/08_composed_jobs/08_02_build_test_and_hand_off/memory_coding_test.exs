defmodule Jido.Realm.Integration.MemoryCodingTest do
  use ExUnit.Case

  alias Jido.Realm.{Artifacts, Placement, Runner, Session}
  alias Jido.Realm.Conformance.{ArtifactBrowser, BindingFixture, Files, Scenarios}

  defmodule CodingAgent do
    use Jido.Agent, name: "realm_memory_coding", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:work, profile: :program)
    end
  end

  @page """
  <!doctype html>
  <link rel="stylesheet" href="report.css">
  <button id="show">Show total</button>
  <output id="total">Hidden</output>
  <script src="report.js"></script>
  """

  @script """
  document.querySelector('#show').addEventListener('click', () => {
    document.querySelector('#total').textContent = 'Total: 42';
  });
  document.body.dataset.origin = self.origin;
  """

  @artifact %{entrypoint: "index.html", paths: ["index.html", "report.css", "report.js"]}
  @css "#total { color: rgb(12, 34, 56); }"

  setup do
    start_supervised!({Jido, name: __MODULE__})
    :ok
  end

  @tag :browser
  test "the DSL builds a reviewable artifact in Memory and the browser opens it after close" do
    {agent, store} = start_coding(%{lua: {Runner.Lua, []}})

    call(agent, "realm.open", %{}, "realm.opened")

    write(agent, "build.lua", """
    assert(realm.write("index.html", [=[#{@page}]=]))
    assert(realm.write("report.css", [=[#{@css}]=]))
    assert(realm.write("report.js", [=[#{@script}]=]))
    """)

    assert %{status: :succeeded, published: ["index.html", "report.css", "report.js"]} =
             call(
               agent,
               "realm.program.run",
               %{runtime: :lua, entrypoint: "build.lua"},
               "realm.program.result"
             )

    first = call(agent, "realm.artifact.publish", @artifact, "realm.artifact.published")
    Files.assert_reply(agent, :edit, "report.css", %{realm: :work, content: "body {}"})
    second = call(agent, "realm.artifact.publish", @artifact, "realm.artifact.published")
    refute first.revision == second.revision
    call(agent, "realm.close", %{}, "realm.closed")

    assert {:ok, %{content: @css}} = Artifacts.read(store, :reviewer, first.id, "report.css")

    assert {:ok, %{content: "body {}"}} =
             Artifacts.read(store, :reviewer, second.id, "report.css")

    assert {:error, :not_found} = Artifacts.read(store, :stranger, first.id)

    assert {"artifact loaded, styled, and interactive\n", 0} =
             store |> ArtifactBrowser.serve(first.id) |> ArtifactBrowser.review()
  end

  @tag :docker
  test "Bash, Python and Node exchange project files with the same RAM-backed Realm" do
    {agent, store} =
      start_coding(%{
        bash: docker("JIDO_REALM_BASH_IMAGE", "bash:5.2"),
        python: docker("JIDO_REALM_PYTHON_IMAGE", "python:3.13-alpine"),
        javascript: docker("JIDO_REALM_JAVASCRIPT_IMAGE", "node:22-alpine")
      })

    assert %{capabilities: capabilities} = call(agent, "realm.open", %{}, "realm.opened")
    assert [:bash, :python, :javascript] -- capabilities == []
    Files.assert_reply(agent, :mkdir, "report", %{realm: :work})
    write(agent, "report/seed.txt", "40\n")
    write(agent, "report/private.txt", "private notes")

    write(agent, "report/build.sh", """
    set -eu
    grep -q ' /workspace .* - tmpfs ' /proc/self/mountinfo
    test ! -e private.txt
    read -r base < seed.txt
    printf '%s' "$((base + 1))" > 'total data.txt'
    printf '%s' "$1"
    printf 'temporary' > transient.txt
    """)

    write(agent, "report/build.py", """
    from pathlib import Path
    total = int(Path("total data.txt").read_text()) + 1
    Path("total data.txt").write_text(str(total))
    """)

    write(agent, "report/build.js", """
    const fs = require('node:fs');
    const total = fs.readFileSync('total data.txt', 'utf8');
    fs.writeFileSync('index.html', '<h1>Total: ' + total + '</h1>');
    """)

    assert %{status: :succeeded, output: "literal $(false)", published: ["report/total data.txt"]} =
             run(agent, :bash, "build.sh", ["seed.txt"], ["total data.txt"], ["literal $(false)"])

    Files.assert_rejected(agent, :read, "report/transient.txt", :not_found, %{realm: :work})

    assert %{status: :succeeded, published: ["report/total data.txt"]} =
             run(agent, :python, "build.py", ["total data.txt"], ["total data.txt"])

    assert %{status: :succeeded, published: ["report/index.html"]} =
             run(agent, :javascript, "build.js", ["total data.txt"], ["index.html"])

    request = %{entrypoint: "report/index.html", paths: ["report/index.html"]}
    artifact = call(agent, "realm.artifact.publish", request, "realm.artifact.published")
    call(agent, "realm.close", %{}, "realm.closed")
    assert {:ok, %{content: "<h1>Total: 42</h1>"}} = Artifacts.read(store, :reviewer, artifact.id)
  end

  test "the DSL reports invalid lifecycle data, an unopened Realm and unsupported outputs" do
    {agent, _store} = start_coding(%{lua: {Runner.Lua, []}})
    reject(agent, "realm.open", %{paths: []}, :invalid_workspace_options)
    reject(agent, "realm.artifact.publish", @artifact, :session_closed)
    call(agent, "realm.open", %{}, "realm.opened")
    reject(agent, "realm.artifact.publish", %{paths: []}, :invalid_workspace_options)
    write(agent, "run.lua", "print('ok')")

    reject(
      agent,
      "realm.program.run",
      %{runtime: :lua, entrypoint: "run.lua", outputs: ["out.txt"]},
      :unsupported_run_outputs
    )

    for outputs <- [["out.txt", "out.txt"], ["../escape.txt"]] do
      reject(
        agent,
        "realm.program.run",
        %{runtime: :lua, entrypoint: "run.lua", outputs: outputs},
        :invalid_run_options
      )
    end
  end

  test "declared program outputs require the write grant" do
    {agent, _store} = start_coding(%{lua: {Runner.Lua, []}}, [:open, :read, :run])
    call(agent, "realm.open", %{}, "realm.opened")

    reject(
      agent,
      "realm.program.run",
      %{runtime: :lua, entrypoint: "run.lua", outputs: ["out.txt"]},
      :permission_denied
    )
  end

  @tag :docker
  test "failed commands and invalid outputs leave the Memory file tree unchanged" do
    {agent, _store} = start_coding(%{bash: docker("JIDO_REALM_BASH_IMAGE", "bash:5.2")})
    call(agent, "realm.open", %{}, "realm.opened")
    write(agent, "out.txt", "original")

    for {code, status, exit_code} <- [
          {"echo changed > out.txt; exit 7", :failed, 7},
          {"echo changed > out.txt; ln -s /etc/passwd extra.txt", :publication_failed, 0},
          {"echo changed > out.txt", :publication_failed, 0},
          {"echo changed > out.txt; printf '\\377' > extra.txt", :publication_failed, 0}
        ] do
      write(agent, "verify.sh", code)

      assert %{status: ^status, exit_code: ^exit_code, published: []} =
               call(
                 agent,
                 "realm.program.run",
                 %{runtime: :bash, entrypoint: "verify.sh", outputs: ["out.txt", "extra.txt"]},
                 "realm.program.result"
               )

      Files.assert_reply(agent, :read, "out.txt", %{realm: :work}, %{content: "original"})
      Files.assert_rejected(agent, :read, "extra.txt", :not_found, %{realm: :work})
      Files.assert_reply(agent, :delete, "verify.sh", %{realm: :work})
    end
  end

  @tag :docker
  test "declared inputs and outputs have a byte budget and a timed-out run can be retried" do
    {agent, _store} = start_coding(%{bash: docker("JIDO_REALM_BASH_IMAGE", "bash:5.2")})
    call(agent, "realm.open", %{}, "realm.opened")
    write(agent, "verify.sh", ~S|printf '%s' "$1"; sleep 2; echo late > out.txt|)
    write(agent, "first.txt", String.duplicate("a", 600_000))
    write(agent, "second.txt", String.duplicate("b", 600_000))
    request = %{runtime: :bash, entrypoint: "verify.sh", outputs: ["out.txt"]}

    reject(
      agent,
      "realm.program.run",
      Map.put(request, :inputs, ["first.txt", "second.txt"]),
      :input_limit
    )

    reject(agent, "realm.program.run", Map.put(request, :inputs, ["missing.txt"]), :not_found)

    assert %{status: :timed_out, published: []} =
             call(
               agent,
               "realm.program.run",
               Map.put(request, :timeout_ms, 400),
               "realm.program.result"
             )

    Files.assert_rejected(agent, :read, "out.txt", :not_found, %{realm: :work})

    write(agent, "big.sh", "head -c 1048577 /dev/zero | tr '\\000' x > out.txt")

    assert %{
             status: :publication_failed,
             publication_error: %{reason: :output_limit},
             published: []
           } =
             call(
               agent,
               "realm.program.run",
               Map.merge(request, %{entrypoint: "big.sh", timeout_ms: 5_000}),
               "realm.program.result"
             )

    write(agent, "chatty.sh", "head -c 20000 /dev/zero | tr '\\000' x")

    assert %{status: :resource_limit, truncated: true, output: output, published: []} =
             call(
               agent,
               "realm.program.run",
               %{request | entrypoint: "chatty.sh"},
               "realm.program.result"
             )

    assert byte_size(output) == Runner.output_limit()

    write(agent, "small.sh", "printf '' > out.txt")

    assert %{status: :succeeded, published: ["out.txt"]} =
             call(
               agent,
               "realm.program.run",
               %{request | entrypoint: "small.sh"},
               "realm.program.result"
             )

    Files.assert_reply(agent, :read, "out.txt", %{realm: :work}, %{content: ""})

    Files.assert_reply(agent, :mkdir, "-", %{realm: :work})
    write(agent, "-/literal.sh", ~S|printf 'literal path' > "$1"|)
    output_name = "trailing newline\n"

    request = %{
      runtime: :bash,
      entrypoint: "literal.sh",
      cwd: "-",
      args: [output_name],
      outputs: [output_name]
    }

    assert %{status: :succeeded, published: ["-/" <> ^output_name]} =
             call(agent, "realm.program.run", request, "realm.program.result")

    Files.assert_reply(agent, :read, "-/" <> output_name, %{realm: :work}, %{
      content: "literal path"
    })
  end

  @tag :docker
  test "a concurrent file edit wins over a Docker run's stale output" do
    test = self()

    hook = fn
      :read_revision, "out.txt", _, read ->
        result = read.()
        send(test, {:captured_output_revision, self()})

        receive do
          :continue_run -> result
        after
          2_000 -> {:error, :backend_error}
        end

      _, _, _, operation ->
        operation.()
    end

    %{runtime_options: options, seed: seed, observe: observe} =
      BindingFixture.prepare(%{
        realm: :work,
        fixture_options: [
          kind: :memory,
          runners: %{bash: docker("JIDO_REALM_BASH_IMAGE", "bash:5.2")},
          files: %{"revise.sh" => "printf new > out.txt", "out.txt" => "original"},
          hook: hook
        ]
      })

    agent = Scenarios.start_agent(__MODULE__, CodingAgent, %{work: options})
    call(agent, "realm.open", %{}, "realm.opened")
    request = %{runtime: :bash, entrypoint: "revise.sh", outputs: ["out.txt"]}

    running =
      Task.async(fn -> call(agent, "realm.program.run", request, "realm.program.result") end)

    assert_receive {:captured_output_revision, worker}, 2_000
    seed.("out.txt", "concurrent")
    send(worker, :continue_run)

    assert %{status: :publication_failed, publication_error: %{reason: :conflict}, published: []} =
             Task.await(running, 8_000)

    assert observe.("out.txt") == {:ok, "concurrent"}
  end

  defp start_coding(runners, grants \\ :all) do
    store = start_supervised!({Artifacts, viewers: [:reviewer]})
    session = start_supervised!({Session, provider: {Placement, :memory}, runners: runners})
    options = [session: session, presenter: {Artifacts, store}, grants: grants]
    {Scenarios.start_agent(__MODULE__, CodingAgent, %{work: options}), store}
  end

  defp docker(env, default) do
    {Runner.Docker,
     image: System.get_env(env, default),
     context: System.get_env("JIDO_REALM_DOCKER_CONTEXT"),
     workspace: :memory}
  end

  defp write(agent, path, content),
    do: Files.assert_reply(agent, :create, path, %{realm: :work, content: content})

  defp run(agent, runtime, entrypoint, inputs, outputs, args \\ []) do
    call(
      agent,
      "realm.program.run",
      %{
        runtime: runtime,
        entrypoint: entrypoint,
        cwd: "report",
        inputs: inputs,
        outputs: outputs,
        args: args,
        timeout_ms: 5_000
      },
      "realm.program.result"
    )
  end

  defp call(agent, type, params, reply_type) do
    assert {:ok, %{status: :committed, reply: %{type: ^reply_type, data: data}}} =
             signal(agent, type, params)

    data
  end

  defp reject(agent, type, params, reason) do
    assert {:ok, %{status: :failed, reply: nil, error: %{details: %{reason: ^reason}}}} =
             signal(agent, type, params)
  end

  defp signal(agent, type, params) do
    signal = Jido.Signal.new!(type, Map.put(params, :realm, :work), source: "/test")
    Jido.AgentServer.call(agent, signal, timeout: 12_000)
  end
end
