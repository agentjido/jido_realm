defmodule Jido.Realm.Conformance.SpriteAppFixture do
  @moduledoc false

  @behaviour Jido.Realm.Runner
  @behaviour Jido.Realm.Preview

  alias Jido.Realm.{Local, Runner}
  alias Jido.Realm.Runner.Snapshot
  alias Sprites.Filesystem

  @root "/home/sprite"
  @seen_timeout 15_000

  @impl Jido.Realm.Runner
  def prepare(runtime, %{binding: {Local, root}, ownership: :owned}, opts)
      when runtime in [:bash, :javascript] do
    sprite = Keyword.fetch!(opts, :sprite)
    version = if runtime == :bash, do: "elixir --version", else: "node --version"

    with {:ok, versions} <- run(sprite, "bash", ["-lc", version], @seen_timeout) do
      {:ok,
       %{
         sprite: sprite,
         cli: Keyword.fetch!(opts, :cli),
         runtime: runtime,
         root: root,
         inputs: %{files: Keyword.fetch!(opts, :files), directories: []},
         toolchain: %{sprite: sprite.name, runtime: runtime, versions: versions}
       }}
    end
  end

  def prepare(_, _, _), do: {:error, :runtime_unavailable}

  @impl Jido.Realm.Preview
  def prepare(lease, opts), do: prepare(Keyword.fetch!(opts, :runtime), lease, opts)

  @impl Jido.Realm.Runner
  def controls(_), do: [:checked_source]

  @impl Jido.Realm.Runner
  def execute(config, %{kind: :check} = request, _grants) do
    with {:ok, source, workdir} <- snapshot(config, request.resource_id, request[:source_ref]) do
      {binary, args} = command(request)

      result =
        case remote(config.sprite, binary, args, request.timeout_ms, dir: workdir) do
          {output, 0} -> Runner.result(:succeeded, 0, output)
          {output, 124} -> Runner.result(:timed_out, nil, output)
          {output, code} when is_integer(code) -> Runner.result(:test_failed, code, output)
          {:error, _} -> :unknown
        end

      case result do
        :unknown -> {:error, :unknown}
        result -> {:ok, Map.merge(result, source)}
      end
    end
  end

  def execute(_, _, _), do: {:error, :unsupported_run_options}

  @impl Jido.Realm.Preview
  def verified_source?(_), do: true

  @impl Jido.Realm.Preview
  def start(config, %{kind: :service} = request) do
    with {:ok, _, workdir} <- snapshot(config, request.id, request[:source_ref]) do
      handle = %{sprite: config.sprite, dir: workdir, port: request.port, proxy: nil}
      {binary, args} = command(request)
      owner = spawn(fn -> drain() end)

      launch = """
      set -eu
      stamp=$(awk '{print $22}' "/proc/$$/stat")
      printf '%s %s\n' "$$" "$stamp" > .service-pid
      exec "$@"
      """

      options = [
        dir: workdir,
        owner: owner,
        env: [{"PORT", Integer.to_string(request.port)}]
      ]

      case Sprites.spawn(
             config.sprite,
             "timeout",
             ["--kill-after=5s", "180s", "bash", "-c", launch, "realm-service", binary | args],
             options
           ) do
        {:ok, running} ->
          launch_preview(config, Map.put(handle, :command, running), request.timeout_ms)

        {:error, _} ->
          Process.exit(owner, :shutdown)
          {:error, {:service_cleanup_unknown, request.id}, handle}
      end
    end
  end

  def start(_, _), do: {:error, :unsupported_run_options}

  @impl Jido.Realm.Preview
  def stop(_config, handle) do
    close_proxy(handle.proxy)

    script = """
    set -eu
    if test -f .service-pid; then
      read -r pid stamp < .service-pid
      same_process() {
        test -n "$stamp" && test "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" = "$stamp"
      }
      if same_process; then kill -TERM "$pid" 2>/dev/null || true; fi
      for attempt in $(seq 1 40); do
        same_process || break
        sleep 0.25
      done
      if same_process; then
        kill -KILL "$pid"
        sleep 0.25
        if same_process; then exit 1; fi
      fi
    fi
    if curl -sS --max-time 2 "http://127.0.0.1:$1/" >/dev/null 2>&1; then
      exit 2
    else
      test "$?" -eq 7
    fi
    """

    case run(handle.sprite, "bash", ["-c", script, "realm-stop", "#{handle.port}"], @seen_timeout,
           dir: handle.dir
         ) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :unknown}
    end
  end

  @impl Jido.Realm.Preview
  def running?(%{proxy: pid, command: %{pid: command}}) when is_pid(pid),
    do: Process.alive?(pid) and Process.alive?(command)

  def running?(_), do: false

  def process_identity(sprite, port) do
    script = """
    set -eu
    curl -fsS --max-time 3 "http://127.0.0.1:$1/" >/dev/null
    for record in /home/sprite/realm-service-test/*/.service-pid; do
      read -r pid stamp < "$record"
      if test -n "$stamp" && test "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" = "$stamp"; then
        printf '%s %s\n' "$pid" "$stamp"
        exit 0
      fi
    done
    exit 1
    """

    run(sprite, "bash", ["-c", script, "realm-process", "#{port}"], @seen_timeout)
  end

  defp snapshot(config, id, expected) do
    local = Path.join(System.tmp_dir!(), "realm-sprite-stage-" <> id)
    path = "realm-service-test/" <> id
    fs = Sprites.filesystem(config.sprite, @root)

    with :ok <- File.mkdir(local) do
      try do
        with {:ok, source} <-
               Snapshot.capture(config.root, config.inputs, config.toolchain, local),
             :ok <- verify_source(expected, source.source_ref),
             :ok <- upload(fs, local, path, Map.keys(source.inputs)) do
          {:ok, source, Path.join(@root, path)}
        end
      after
        File.rm_rf(local)
      end
    end
  end

  defp verify_source(nil, _), do: :ok
  defp verify_source(reference, reference), do: :ok
  defp verify_source(_, _), do: {:error, :stale_source}

  defp upload(fs, local, path, files) do
    Enum.reduce_while(files, :ok, fn name, :ok ->
      with {:ok, bytes} <- File.read(Path.join(local, name)),
           :ok <- Filesystem.write(fs, Path.join(path, name), bytes) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :sprite_upload_failed}}
      end
    end)
  end

  defp command(%{runtime: :javascript, entrypoint: file, args: args}),
    do: {"node", ["--experimental-strip-types", "./" <> file | args]}

  defp command(%{runtime: :bash, command: script}), do: {"bash", ["-lc", script]}

  defp launch_preview(config, handle, timeout) do
    # sprites-ex 0.2.4 accepts the TCP socket in a process that dispatches to
    # itself. Use the signed-in CLI for the loopback TCP transport only.
    with {:ok, port} <- local_port(),
         {:ok, pid, _os_pid} <- proxy(config, handle, port) do
      handle = %{handle | proxy: pid}

      if wait_ready(port, handle, System.monotonic_time(:millisecond) + timeout) do
        {:ok, handle, %{host: "127.0.0.1", port: port}}
      else
        {:error, :sprite_service_not_ready, handle}
      end
    else
      _ -> {:error, :sprite_proxy_unavailable, handle}
    end
  end

  defp proxy(config, handle, port) do
    org_args = if org = System.get_env("SPRITES_TEST_ORG"), do: ["-o", org], else: []
    args = org_args ++ ["-s", config.sprite.name, "proxy", "#{port}:#{handle.port}"]

    :exec.run([config.cli | args], [
      {:group, 0},
      :kill_group,
      {:stdin, :close},
      {:env, [{"UPGRADE_CHECK", "false"}]}
    ])
  end

  defp close_proxy(pid) when is_pid(pid) do
    if Process.alive?(pid), do: :exec.stop_and_wait(pid, 3_000)
  catch
    :exit, _ -> :unknown
  end

  defp close_proxy(_), do: :ok

  defp local_port do
    with {:ok, socket} <- :gen_tcp.listen(0, ip: {127, 0, 0, 1}),
         {:ok, port} <- :inet.port(socket),
         :ok <- :gen_tcp.close(socket) do
      {:ok, port}
    end
  end

  defp wait_ready(port, handle, deadline) do
    cond do
      not running?(handle) ->
        false

      System.monotonic_time(:millisecond) >= deadline ->
        false

      match?(
        {:ok, %{status: 200}},
        Req.get("http://127.0.0.1:#{port}/",
          retry: false,
          receive_timeout: 2_000,
          connect_options: [timeout: 500]
        )
      ) ->
        true

      true ->
        Process.sleep(250)
        wait_ready(port, handle, deadline)
    end
  end

  defp drain do
    receive do
      {channel, _, _} when channel in [:stdout, :stderr] -> drain()
      {channel, _, _} when channel in [:exit, :error] -> :ok
    after
      185_000 -> :ok
    end
  end

  defp run(sprite, binary, args, timeout, opts \\ []) do
    case remote(sprite, binary, args, timeout, opts) do
      {output, 0} -> {:ok, String.trim(output)}
      {_, code} when is_integer(code) -> {:error, {:sprite_command_failed, code}}
      {:error, _} = error -> error
    end
  end

  defp remote(sprite, binary, args, timeout, opts) do
    seconds = "#{div(timeout + 999, 1000)}s"

    Sprites.cmd(
      sprite,
      "timeout",
      ["--kill-after=3s", seconds, binary | args],
      [timeout: timeout + 12_000, stderr_to_stdout: true] ++ opts
    )
  rescue
    _ -> {:error, :sprite_transport}
  end
end
