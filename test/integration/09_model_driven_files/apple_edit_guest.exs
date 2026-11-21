defmodule Jido.Realm.AppleEdit.Guest do
  @moduledoc false

  import ExUnit.Assertions

  alias Jido.Realm
  alias Jido.Realm.Preview

  @setup """
  cmp -s mix.exs /opt/realm/setup/mix.exs &&
    cmp -s mix.lock /opt/realm/setup/mix.lock || exit 78
  mkdir -p "$MIX_BUILD_PATH" &&
    cp -r /opt/realm/build/. "$MIX_BUILD_PATH" &&
    chmod -R u+w "$MIX_BUILD_PATH" || exit 78
  """

  def new(root, evidence, id, engine) do
    workspace = Path.join(root, "workspace")
    {:ok, state} = Agent.start_link(fn -> %{round: 0, verified_by: nil} end)
    %{workspace: workspace, evidence: evidence, id: id, engine: engine, state: state}
  end

  def options(guest) do
    image = System.get_env("JIDO_REALM_CODING_IMAGE", "jido-realm-coding:local")

    options = [
      image: image,
      probe: "bash --version && mix --version",
      grep: true,
      env: %{"MIX_BUILD_PATH" => "/tmp/realm-build"},
      check_exits: %{78 => :setup_failed},
      files: ["mix.exs", "mix.lock"],
      directories: ["lib", "test"],
      network: "jido-realm-coding-preview-local"
    ]

    adapter =
      case guest.engine do
        :docker -> {Jido.Realm.Runner.Docker, staged: options}
        :apple_container -> {Jido.Realm.Runner.AppleContainer, options}
      end

    record(guest, %{kind: "configuration", engine: guest.engine, image: image})

    checks = %{"project" => %{command: @setup <> "mix test"}}

    checks =
      Enum.reduce(0..3, checks, fn round, checks ->
        Map.put(checks, "acceptance-#{round}", %{
          command: @setup <> "mix test /opt/realm/acceptance/round_test.exs",
          env: %{"REALM_EDIT_ROUND" => Integer.to_string(round)}
        })
      end)

    [
      runners: %{bash: adapter},
      preview: adapter,
      preview_base_url: "http://127.0.0.1",
      preview_viewers: [:reviewer],
      commands: %{
        verify: %{
          grant: :run,
          schema: Jido.Joi.object(%{}),
          exec: {:check, :bash, @setup <> "mix test"}
        }
      },
      services: %{
        app: %{
          exec: {:shell, :bash, @setup <> "mix run --no-halt"},
          ports: %{http: 8080},
          require_check: :verify
        }
      },
      max_run_ms: 30_000,
      coding: [
        bash: true,
        write_paths:
          ~r/\A(?:lib\/realm_demo\/[a-z][a-z0-9_]*\.ex|test\/[a-z][a-z0-9_]*_test\.exs)\z/,
        checks: checks,
        services: %{"app" => @setup <> "mix run --no-halt", "failing" => "exit 23"}
      ]
    ]
  end

  def workspace(guest), do: guest.workspace
  def round(guest, value), do: Agent.update(guest.state, &%{&1 | round: value})

  def prepare(guest), do: shell(guest, "toolchain", "bash --version; rg --version; mix --version")

  def mount_check(guest) do
    shell(guest, "mount", """
    set -eu
    test -f /workspace/mix.exs
    test "$(ls /sys/class/net)" = lo
    test "$(id -u)" = 65534
    test ! -e /workspace/host-only
    if touch /workspace/guest-write-probe 2>/dev/null; then exit 1; fi
    touch /tmp/scratch
    """)
  end

  def shell(guest, kind, command) do
    {:ok, result} = Realm.exec(guest.context, :work, {:shell, :bash, command})
    record(guest, Map.put(result, :kind, kind))
    result
  end

  def check(guest, "acceptance") do
    round = Agent.get(guest.state, & &1.round)
    check(guest, "acceptance-#{round}")
  end

  def check(guest, "project") do
    assert {:ok, result} = Realm.exec(guest.context, :work, {:command, :verify, %{}})
    record(guest, Map.put(result, :kind, "project"))

    if result.status == :succeeded do
      Agent.update(guest.state, &%{&1 | verified_by: result.id})
    end

    result
  end

  def check(guest, kind) do
    assert {:ok, result} = Realm.coding_run(guest.context, :work, :check, %{name: kind})
    record(guest, Map.put(result, :kind, kind))
    result
  end

  def preview(guest, observe) do
    check_id = Agent.get(guest.state, & &1.verified_by)

    assert {:ok, %{id: service_id, ports: [:http]}} =
             Realm.start_service(guest.context, :work, :app, verified_by: check_id)

    assert {:error, :not_found} = Preview.target(guest.session, service_id, :reviewer)
    assert {:ok, %{id: id}} = Realm.expose_port(guest.context, :work, service_id, :http)

    assert {:ok, target} = Preview.target(guest.session, id, :reviewer)
    assert {:error, :not_found} = Preview.target(guest.session, id, :stranger)

    {listener, url, key} = gateway(guest.session, id)

    try do
      observe.(url, id, key)
    after
      assert :ok = Realm.close_port(guest.context, :work, id)
      assert {:error, :not_found} = Preview.target(guest.session, id, :reviewer)
      assert {:ok, %{status: 404}} = request(url, key)
      assert {:ok, %{id: new_id}} = Realm.expose_port(guest.context, :work, service_id, :http)
      assert new_id != id
      assert {:ok, ^target} = Preview.target(guest.session, new_id, :reviewer)
      assert :ok = Realm.stop_service(guest.context, :work, service_id)
      assert {:error, :not_found} = Preview.target(guest.session, new_id, :reviewer)
      assert {:error, _} = :gen_tcp.connect({127, 0, 0, 1}, target.port, [], 500)
      assert :ok = :gen_tcp.close(listener)

      record(guest, %{kind: "preview_stop", id: id, gateway_revoked: true, listener_closed: true})
    end
  end

  def request(url, key \\ nil) do
    headers = if key, do: [{"cookie", "realm_viewer=" <> key}], else: []

    Req.get(url,
      headers: headers,
      retry: false,
      redirect: false,
      decode_body: false,
      receive_timeout: 3_000
    )
  end

  def cleanup!(guest) do
    {output, 0} =
      case guest.engine do
        :apple_container -> System.cmd("container", ["list", "--all", "--format", "json"])
        :docker -> System.cmd("docker", ["ps", "-a", "--format", "{{.Names}}"])
      end

    refute output =~ "jido-realm-coding-run-"
    refute output =~ "jido-realm-coding-preview-"
    refute output =~ "jido-realm-probe-"
    record(guest, %{kind: "cleanup", all_absent: true})
  end

  defp gateway(session, id) do
    key = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listener)
    spawn_link(fn -> accept(listener, session, id, key) end)
    {listener, "http://127.0.0.1:#{port}/", key}
  end

  defp accept(listener, session, id, key) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        serve(socket, session, id, key)
        :gen_tcp.close(socket)
        accept(listener, session, id, key)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(socket, session, id, key) do
    with {:ok, {:http_request, :GET, {:abs_path, path}, _}} <- :gen_tcp.recv(socket, 0, 1_000),
         {:ok, cookie} <- cookie(socket, "", 32),
         uri = URI.parse(path),
         query = URI.decode_query(uri.query || ""),
         bootstrap = query["viewer"] == key,
         true <- bootstrap or ("realm_viewer=" <> key) in String.split(cookie, "; ", trim: true),
         {:ok, target} <- Preview.target(session, id, :reviewer),
         url = "http://127.0.0.1:#{target.port}" <> strip_viewer(uri),
         {:ok, response} <- request(url) do
      type = List.first(response.headers["content-type"] || ["text/plain"])

      extra =
        if bootstrap,
          do: "Set-Cookie: realm_viewer=#{key}; Path=/; HttpOnly; SameSite=Strict\r\n",
          else: ""

      respond(socket, response.status, type, response.body, extra)
    else
      _ -> respond(socket, 404, "text/plain", "Not found", "")
    end
  end

  defp strip_viewer(uri) do
    query = (uri.query || "") |> URI.decode_query() |> Map.delete("viewer") |> URI.encode_query()
    if query == "", do: uri.path, else: uri.path <> "?" <> query
  end

  defp cookie(_, _, 0), do: {:error, :headers_limit}

  defp cookie(socket, value, remaining) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, :http_eoh} -> {:ok, value}
      {:ok, {:http_header, _, :Cookie, _, cookie}} -> cookie(socket, cookie, remaining - 1)
      {:ok, {:http_header, _, _, _, _}} -> cookie(socket, value, remaining - 1)
      _ -> {:error, :request_invalid}
    end
  end

  defp respond(socket, status, type, body, extra) do
    reason = if status == 200, do: "OK", else: "Not Found"

    :gen_tcp.send(
      socket,
      [
        "HTTP/1.1 #{status} #{reason}\r\n",
        "Content-Length: #{byte_size(body)}\r\n",
        "Content-Type: #{type}\r\n",
        extra,
        "Connection: close\r\n\r\n",
        body
      ]
    )
  end

  defp record(guest, event) do
    File.write!(Path.join(guest.evidence, "guest-runs.jsonl"), Jason.encode!(event) <> "\n", [
      :append
    ])
  end
end
