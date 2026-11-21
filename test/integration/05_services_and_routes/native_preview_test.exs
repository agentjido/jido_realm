defmodule Jido.Realm.Integration.NativePreviewTest do
  use ExUnit.Case

  alias Jido.Realm
  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.{Plugin, Preview, Profile}

  @moduletag :tmp_dir
  @body "trusted native service"

  @application ~S'''
  {ok, Host} = inet:parse_address(os:getenv("HOST")),
  Port = list_to_integer(os:getenv("PORT")),
  {ok, Listener} = gen_tcp:listen(Port, [binary, {ip, Host}, {active, false}, {reuseaddr, true}]),
  Loop = fun Serve() ->
      {ok, Socket} = gen_tcp:accept(Listener),
      case gen_tcp:recv(Socket, 0, 500) of
          {ok, _} ->
              gen_tcp:send(Socket, <<"HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 22\r\n\r\ntrusted native service">>);
          _ -> ok
      end,
      gen_tcp:close(Socket),
      Serve()
  end,
  Loop().
  '''

  @launch ~S'''
  if [ "$3" = stubborn ]; then
    /bin/sh -c 'trap "" TERM; printf ready > child-ready; exec /bin/sleep 90' &
  else
    /bin/sleep 90 &
  fi
  child=$!
  "$1" +S 2:2 +A 2 -noshell -noinput -eval "$2" &
  server=$!
  clean_up() {
    kill "$server" "$child" 2>/dev/null
    wait "$server" 2>/dev/null
    if [ "$3" != stubborn ]; then wait "$child" 2>/dev/null; fi
    exit 0
  }
  trap 'clean_up "$@"' TERM
  printf '%s %s %s\n' "$$" "$child" "$server" > service-pids
  wait "$server"
  clean_up "$@"
  '''

  defmodule Job do
    use Jido.Action,
      name: "native_preview_job",
      schema:
        Jido.Joi.object(%{
          mode: Jido.Joi.atom(),
          name: Jido.Joi.string(),
          args: Jido.Joi.list(Jido.Joi.string()),
          cwd: Jido.Joi.string(),
          timeout_ms: Jido.Joi.integer()
        })

    @impl true
    def run(%{mode: :start} = input, context) do
      result =
        Jido.Realm.start_preview(context, :work, :native, input.name,
          args: input.args,
          cwd: input.cwd,
          timeout_ms: input.timeout_ms
        )

      reply(result, context)
    end

    def run(%{mode: :stop, name: id}, context) do
      case Jido.Realm.stop_preview(context, :work, id) do
        :ok -> reply({:ok, %{}}, context)
        error -> reply(error, context)
      end
    end

    defp reply({:ok, data}, context) do
      {:ok, signal} = Jido.Agent.build_signal(context, "native.preview.result", data)
      {:ok, context.agent_state, [Jido.Agent.Directive.reply(signal)]}
    end

    defp reply({:error, reason}, _context),
      do:
        {:error, Jido.Error.execution_error("Native preview failed", details: %{reason: reason})}
  end

  defmodule Agent do
    use Jido.Agent, name: "native_preview_agent", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:work, profile: :program)
    end

    routes do
      signal_source("/test/realm/native-preview")
      route("realm.job", AgentJobs.Job)
      route("native.preview", Job)
    end
  end

  setup context do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)

    if context[:occupied] do
      on_exit(fn -> :gen_tcp.close(socket) end)
    else
      :ok = :gen_tcp.close(socket)
    end

    command =
      case context[:service] do
        :failed ->
          ["/bin/sh", "-c", "printf 'native startup failed\\n' >&2; exit 7"]

        :idle ->
          ["/bin/sh", "-c", ~S(printf "%s" "$$" > service-pids; exec /bin/sleep 90)]

        service ->
          erl = Path.join(List.to_string(:code.root_dir()), "bin/erl")
          ["/bin/sh", "-c", @launch, "native-fixture", erl, @application, to_string(service)]
      end

    preview =
      {:native, name: "report", command: command, cwd: context.tmp_dir, port: port}

    binding =
      {BindingFixture,
       kind: :local,
       mode: :owned,
       preview: preview,
       services: %{report: %{exec: {:entrypoint, :native, "report"}, ports: %{http: port}}},
       preview_base_url: "https://review.example.test/preview",
       preview_viewers: [:reviewer],
       grants: Map.get(context, :grants, :all)}

    %{agent: agent, bindings: bindings} =
      Scenarios.prepare(context, Agent, [work: binding], :native)

    assert :preview in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
    assert_receive {:placement_opened, :work, placement}

    %{
      agent: agent,
      session: bindings.work[:session],
      port: port,
      placement: placement,
      pids: Path.join(context.tmp_dir, "service-pids")
    }
  end

  test "05.01 erlexec serves a trusted program and close confirms group cleanup", ctx do
    assert :erlexec in Enum.map(Application.started_applications(), &elem(&1, 0))
    %{id: id, url: url} = started(ctx)
    assert url == "https://review.example.test/preview/#{id}/"
    assert {:ok, %{host: "127.0.0.1", port: port}} = Preview.target(ctx.session, id, :reviewer)
    assert port == ctx.port
    assert {:error, :not_found} = Preview.target(ctx.session, id, :stranger)
    assert @body == http_response(port)
    pids = read_pids(ctx)
    assert Enum.all?(pids, &process_alive?/1)

    assert {:ok, %{status: :committed}} = job(ctx, %{mode: :stop, name: id})
    assert_stopped(ctx, id, pids)
    assert File.dir?(ctx.placement)

    %{id: next_id} = started(ctx)
    next_pids = read_pids(ctx)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
    assert_stopped(ctx, next_id, next_pids)
    assert_receive {:placement_released, :work, :owned}
    refute File.exists?(ctx.placement)
  end

  test "05.01 the trusted erlexec service owns its process independently of the endpoint", ctx do
    {:ok, profile} = Profile.resolve(:program)

    context = %{
      plugin_inputs: %{
        Plugin => %{
          runtime: %{
            bindings: %{
              "work" => %{
                target: {:session, ctx.session, profile},
                grants: [:read, :run, :service, :expose]
              }
            }
          }
        }
      }
    }

    assert {:ok, %{id: service, ports: [:http]}} = Realm.start_service(context, :work, :report)
    assert {:error, :not_found} = Preview.target(ctx.session, service, :reviewer)
    assert {:ok, %{id: endpoint}} = Realm.expose_port(context, :work, service, :http)
    assert {:ok, %{port: port}} = Preview.target(ctx.session, endpoint, :reviewer)
    assert @body == http_response(port)
    pids = read_pids(ctx)

    assert :ok = Realm.close_port(context, :work, endpoint)
    assert {:error, :not_found} = Preview.target(ctx.session, endpoint, :reviewer)
    assert Enum.all?(pids, &process_alive?/1)

    assert {:ok, %{id: replacement}} = Realm.expose_port(context, :work, service, :http)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
    assert_stopped(ctx, replacement, pids)
    assert_receive {:placement_released, :work, :owned}
  end

  test "05.01 revokes access when the native service exits by itself", ctx do
    %{id: id} = started(ctx)
    [_, _, service] = pids = read_pids(ctx)
    assert {_, 0} = System.cmd("/bin/kill", ["-TERM", service])

    assert eventually(fn ->
             Preview.target(ctx.session, id, :reviewer) == {:error, :not_found}
           end)

    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
    assert_stopped(ctx, id, pids)
  end

  test "05.01 the process group stops after an abrupt Realm session exit", ctx do
    %{id: id} = started(ctx)
    pids = read_pids(ctx)
    Process.exit(ctx.session, :kill)
    assert eventually(fn -> Enum.all?(pids, &(not process_alive?(&1))) end)
    assert {:error, :session_closed} = Preview.target(ctx.session, id, :reviewer)
    assert {:error, :econnrefused} = :gen_tcp.connect({127, 0, 0, 1}, ctx.port, [], 100)
    assert File.dir?(ctx.placement)
    refute_received {:placement_released, :work, _}
  end

  test "02.01 the native selector allows only the approved name and host arguments", ctx do
    assert :native_service_unavailable = reason(job(ctx, %{name: "other"}))
    assert :invalid_native_service_options = reason(job(ctx, %{args: ["different"]}))
    assert :invalid_native_service_options = reason(job(ctx, %{cwd: "other"}))
    refute File.exists?(ctx.pids)

    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
  end

  @tag grants: [:open, :close, :run, :read]
  test "02.01 the agent requires the preview grant", ctx do
    assert :permission_denied = reason(job(ctx))
    refute File.exists?(ctx.pids)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
  end

  @tag occupied: true
  test "05.02 the adapter rejects an occupied port before it starts the program", ctx do
    assert :preview_port_unavailable = reason(job(ctx))
    refute File.exists?(ctx.pids)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
  end

  @tag service: :failed
  test "05.02 returns native startup diagnostics with no route", ctx do
    assert {:service_start_failed, %{id: id, reason: :service_exited, output: output}} =
             reason(job(ctx))

    assert output =~ "native startup failed"
    assert {:error, :not_found} = Preview.target(ctx.session, id, :reviewer)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
  end

  @tag service: :idle
  test "05.02 stops a running program that misses its readiness deadline", ctx do
    assert {:service_start_failed, %{id: id, reason: :readiness_timeout}} =
             reason(job(ctx, %{timeout_ms: 200}))

    leader = File.read!(ctx.pids)
    assert_stopped(ctx, id, [leader])
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
  end

  @tag service: :stubborn
  test "05.02 close keeps the lease while a native child remains", ctx do
    %{id: id} = started(ctx)
    [leader, child, _] = read_pids(ctx)
    marker = Path.join(Path.dirname(ctx.pids), "child-ready")
    assert eventually(fn -> File.exists?(marker) end)

    try do
      # The child survives the group signal after the leader exits.
      assert {_, 0} = System.cmd("/bin/kill", ["-KILL", leader])
      assert eventually(fn -> not process_alive?(leader) end)

      assert :cleanup_unconfirmed = reason(job(ctx, %{mode: :stop, name: id}))
      AgentJobs.rejected(ctx.agent, :close, :cleanup_unconfirmed, %{realm: :work})
      assert process_alive?(child)
      assert File.dir?(ctx.placement)
      assert {:error, :not_found} = Preview.target(ctx.session, id, :reviewer)
      refute_received {:placement_released, :work, _}

      Files.assert_rejected(ctx.agent, :create, "blocked.txt", :session_closed, %{
        realm: :work,
        content: "blocked"
      })
    after
      if process_alive?(child), do: System.cmd("/bin/kill", ["-KILL", child])
    end

    assert eventually(fn -> not process_alive?(child) end)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
    assert_receive {:placement_released, :work, :owned}
  end

  defp job(ctx, data \\ %{}) do
    defaults = %{mode: :start, name: "report", args: [], cwd: ".", timeout_ms: 4_000}
    signal = Jido.Signal.new!("native.preview", Map.merge(defaults, data), source: "/test")
    Jido.AgentServer.call(ctx.agent, signal, timeout: 8_000)
  end

  defp started(ctx) do
    assert {:ok, %{status: :committed, reply: %{data: route}}} = job(ctx)
    route
  end

  defp reason({:ok, %{status: :failed, reply: nil, error: %{details: %{reason: reason}}}}),
    do: reason

  defp read_pids(ctx) do
    [_, _, _] = pids = ctx.pids |> File.read!() |> String.split()
    pids
  end

  defp assert_stopped(ctx, id, pids) do
    refute Enum.any?(pids, &process_alive?/1)
    assert {:error, :not_found} = Preview.target(ctx.session, id, :reviewer)
    assert {:error, :econnrefused} = :gen_tcp.connect({127, 0, 0, 1}, ctx.port, [], 100)
  end

  defp process_alive?(pid),
    do: match?({_, 0}, System.cmd("/bin/kill", ["-0", pid], stderr_to_stdout: true))

  defp http_response(port) do
    url = ~c"http://127.0.0.1:#{port}/"
    assert {:ok, {{_, 200, _}, _, body}} = :httpc.request(url)
    List.to_string(body)
  end

  defp eventually(fun, attempts \\ 120)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(20)
      eventually(fun, attempts - 1)
    end
  end
end
