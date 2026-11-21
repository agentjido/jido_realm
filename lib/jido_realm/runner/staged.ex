defmodule Jido.Realm.Runner.Staged do
  @moduledoc false

  alias Jido.Realm.{Local, Preview, Runner}
  alias Jido.Realm.Runner.Snapshot

  @control_ms 8_000
  @default_port 8080
  @interpreters %{
    bash: {"/bin/bash", ["--noprofile", "--norc"]},
    python: {"/usr/local/bin/python3", ["-B"]},
    javascript: {"/usr/local/bin/node", []}
  }

  def prepare(engine, runtime, %{binding: {Local, root}, ownership: :owned}, opts)
      when is_map_key(@interpreters, runtime) and is_list(opts) do
    {binary, flags} = Map.fetch!(@interpreters, runtime)

    with true <- Keyword.keyword?(opts),
         {:ok, transport} <- engine.connect(opts),
         image when is_binary(image) and image != "" <- opts[:image],
         {:ok, identity} <- engine.image_identity(transport, image),
         {:ok, inputs} <- inputs(opts),
         {:ok, runtime_options} <- runtime_options(runtime, binary, flags, opts),
         config =
           Map.merge(runtime_options, %{
             engine: engine,
             transport: transport,
             root: root,
             image: image,
             identity: identity,
             inputs: inputs,
             runtime: runtime
           }),
         {:ok, tools} <- probe(config) do
      key =
        :erlang.term_to_binary({engine, runtime, config.binary, config.flags, config.env}, [
          :deterministic
        ])

      toolchain = %{
        image: identity,
        versions: tools,
        configuration: Jido.Realm.Tree.revision(key)
      }

      {:ok, Map.put(config, :toolchain, toolchain)}
    else
      _ -> {:error, :runtime_unavailable}
    end
  end

  def prepare(_, _, _, _), do: {:error, :unsupported_runtime}

  def prepare_service(engine, lease, opts) do
    with {:ok, config} <- prepare(engine, Keyword.get(opts, :runtime, :bash), lease, opts),
         :ok <- engine.preview_network(config.transport) do
      {:ok, config}
    end
  end

  defp runtime_options(runtime, binary, flags, opts) do
    binary = Keyword.get(opts, :binary, binary)
    flags = Keyword.get(opts, :flags, flags)
    env = Keyword.get(opts, :env, %{})
    check_exits = Keyword.get(opts, :check_exits, %{})
    grep? = Keyword.get(opts, :grep, false)
    probe = opts[:probe]

    with true <- is_binary(binary) and Path.type(binary) == :absolute,
         true <- is_list(flags) and Enum.all?(flags, &is_binary/1),
         true <- is_map(env) and Enum.all?(env, fn {k, v} -> is_binary(k) and is_binary(v) end),
         true <-
           is_map(check_exits) and
             Enum.all?(check_exits, fn {k, v} ->
               is_integer(k) and v in [:test_failed, :setup_failed]
             end),
         true <- is_boolean(grep?) and (runtime == :bash or not grep?),
         true <- is_nil(probe) or (runtime == :bash and is_binary(probe)) do
      {:ok,
       %{
         binary: binary,
         flags: flags,
         env: env,
         check_exits: check_exits,
         grep?: grep?,
         probe: probe
       }}
    else
      _ -> {:error, :invalid_run_options}
    end
  end

  def controls(config) do
    common = [
      :checked_source,
      :read_only_inputs,
      :private_scratch,
      :loopback_only,
      :non_root,
      :bounded_progress
    ]

    common = if config.runtime == :bash, do: [:bash_command | common], else: common
    if config.grep?, do: [:native_grep | common], else: common
  end

  def execute(config, request, _grants) do
    kind = Map.get(request, :kind, :entrypoint)
    requested_files = [Map.get(request, :entrypoint) | Map.get(request, :inputs) || []]
    guarded(fn watch -> run_snapshot(config, request, requested_files, kind, watch) end)
  end

  defp run_snapshot(config, request, files, kind, watch) do
    handle = handle(request.resource_id, "run")

    with :ok <- File.mkdir(handle.stage) do
      with {:ok, source} <-
             Snapshot.capture(config.root, config.inputs, config.toolchain, handle.stage),
           :ok <- compare_source(request, source),
           :ok <- check_directory(handle, request),
           :ok <- check_files(handle, request, files) do
        result = execute_guest(config, request, handle, watch)
        finish_run(config, handle, result, source, kind)
      else
        {:error, reason} ->
          File.rm_rf(handle.stage)
          {:error, reason}
      end
    end
  end

  def start(%{runtime: runtime} = config, %{kind: kind, runtime: runtime} = request)
      when kind in [:checked_preview, :service] do
    handle = handle(request.id, "preview")

    with :ok <- File.mkdir(handle.stage) do
      case launch_preview(config, request, handle) do
        {:ok, port} ->
          handle =
            Map.merge(handle, %{port: port, engine: config.engine, transport: config.transport})

          {:ok, handle, %{host: "127.0.0.1", port: port}}

        {:error, {:unknown, _} = reason} ->
          {:error, {:service_cleanup_unknown, request.id, reason}, handle}

        {:error, reason} ->
          case stop(config, handle) do
            :ok -> {:error, reason}
            {:error, _} -> {:error, {:service_cleanup_unknown, request.id, reason}, handle}
          end
      end
    end
  end

  def start(_, _), do: {:error, :checked_source_required}

  def stop(%{engine: engine, transport: transport}, handle) do
    with true <-
           engine.remove(transport, handle.name) == :ok or engine.absent?(transport, handle.name),
         {:ok, _} <- File.rm_rf(handle.stage) do
      :ok
    else
      _ -> {:error, :unknown}
    end
  end

  def running?(handle),
    do: handle.engine.running?(handle.transport, handle.name) and Preview.ready?(handle.port)

  def reconcile(config, request), do: stop(config, handle(request.resource_id, "run"))

  defp inputs(opts) do
    files = Keyword.get(opts, :files, [])
    dirs = Keyword.get(opts, :directories, [])

    if is_list(files) and is_list(dirs) and files ++ dirs != [] and
         length(files) + length(dirs) <= 64 and
         Enum.all?(files, &(Runner.validate_path(&1) == :ok)) and
         Enum.all?(dirs, &(&1 == "." or Runner.validate_path(&1) == :ok)) do
      {:ok, %{files: files, directories: dirs}}
    else
      {:error, :invalid_inputs}
    end
  end

  defp probe(config) do
    with {:ok, stage} <- temporary_stage() do
      name = "jido-realm-probe-" <> Path.basename(stage)
      handle = %{name: name, stage: stage, port: nil}
      request = %{cwd: ".", probe: probe_args(config), timeout_ms: @control_ms}
      site = create(config, request, handle, :run, nil)

      result =
        case site do
          :ok -> config.engine.attach(config.transport, handle.name, request.timeout_ms, nil)
          error -> error
        end

      with :ok <- stop(config, handle),
           {0, output} <- result do
        {:ok, String.trim(output)}
      end
    end
  end

  defp probe_args(%{probe: nil, grep?: false}), do: ["--version"]

  defp probe_args(%{probe: script, grep?: grep?}) do
    command = script || "bash --version"
    command = if grep?, do: command <> " && rg --version", else: command
    ["-c", command]
  end

  defp temporary_stage do
    id = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    stage = Path.join(System.tmp_dir!(), id)
    with :ok <- File.mkdir(stage), do: {:ok, stage}
  end

  defp guarded(run) do
    caller = self()
    tag = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        watch = Process.monitor(caller)
        send(caller, {tag, run.(watch)})
      end)

    receive do
      {^tag, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^pid, _} ->
        {:error, :unknown}
    end
  end

  defp handle(id, type) do
    name = "jido-realm-coding-#{type}-#{id}"
    %{name: name, stage: Path.join(System.tmp_dir!(), name), port: nil}
  end

  defp compare_source(%{source_ref: expected}, %{source_ref: actual})
       when is_binary(expected) and expected != actual,
       do: {:error, :stale_source}

  defp compare_source(_, _), do: :ok

  defp check_directory(_handle, %{cwd: "."}), do: :ok

  defp check_directory(handle, %{cwd: path}) do
    if File.dir?(Path.join(handle.stage, path)), do: :ok, else: {:error, :not_found}
  end

  defp execute_guest(config, request, handle, watch) do
    with :ok <- create(config, request, handle, :run, watch) do
      config.engine.attach(
        config.transport,
        handle.name,
        request.timeout_ms,
        watch,
        request[:on_output]
      )
    end
  end

  defp finish_run(config, handle, result, source, kind) do
    with :ok <- stop(config, handle) do
      case result do
        {0, output} ->
          outcome(:succeeded, 0, output, source)

        {1, output} when kind == :grep ->
          outcome(:succeeded, 1, output, source)

        {code, output} when is_integer(code) ->
          status =
            if kind == :check, do: Map.get(config.check_exits, code, :test_failed), else: :failed

          outcome(status, code, output, source)

        {:timed_out, output} ->
          outcome(:timed_out, nil, output, source)

        {:output_limit, output} ->
          {:ok, Map.merge(Runner.result(:resource_limit, nil, output, true), source)}

        {:error, {:launch_failed, output}} ->
          outcome(:setup_failed, nil, output, source)

        _ ->
          {:error, :unknown}
      end
    end
  end

  defp outcome(status, code, output, source),
    do: {:ok, Map.merge(Runner.result(status, code, output), source)}

  defp launch_preview(%{engine: engine, transport: transport} = config, request, handle) do
    guest_port = Map.get(request, :port, @default_port)

    with {:ok, source} <-
           Snapshot.capture(config.root, config.inputs, config.toolchain, handle.stage),
         :ok <- compare_source(request, source),
         :ok <- check_directory(handle, request),
         :ok <- check_files(handle, request, [request[:entrypoint]]),
         {:ok, port} <- engine.host_port(transport),
         handle = %{handle | port: port},
         :ok <- create(config, request, handle, :preview, nil),
         {0, _} <- engine.boot(transport, handle.name),
         {:ok, port} <- service_port(config, handle, guest_port),
         :ok <- wait_ready(config, handle.name, port, now() + request.timeout_ms) do
      {:ok, port}
    else
      {:error, :unknown} -> {:error, {:unknown, request.id}}
      {:error, reason} -> {:error, reason}
      {_, output} -> {:error, {:service_start_failed, String.replace_invalid(output, "?")}}
    end
  end

  defp service_port(%{engine: engine, transport: transport}, handle, guest_port) do
    case engine.published_port(transport, handle.name, guest_port, handle.port) do
      {:ok, _} = ok ->
        ok

      error ->
        if engine.running?(transport, handle.name),
          do: error,
          else: service_exited(engine, transport, handle.name)
    end
  end

  defp wait_ready(%{engine: engine, transport: transport} = config, name, port, deadline) do
    cond do
      now() >= deadline ->
        {:error, :readiness_timeout}

      not engine.running?(transport, name) ->
        service_exited(engine, transport, name)

      Preview.ready?(port) ->
        :ok

      true ->
        Process.sleep(100)
        wait_ready(config, name, port, deadline)
    end
  end

  defp service_exited(engine, transport, name),
    do: {:error, {:service_exited, engine.logs(transport, name)}}

  defp check_files(handle, request, paths) do
    files = Enum.reject(paths, &is_nil/1)

    if Enum.all?(files, &File.regular?(Path.join(handle.stage, Runner.rooted(request.cwd, &1)))),
      do: :ok,
      else: {:error, :not_found}
  end

  defp create(%{engine: engine, transport: transport} = config, request, handle, mode, watch) do
    with {:ok, identity} when identity == config.identity <-
           engine.image_identity(transport, config.image),
         false <- String.contains?(handle.stage, [",", "\""]) do
      cwd = if request.cwd == ".", do: "/workspace", else: "/workspace/" <> request.cwd

      mount =
        "type=bind,source=#{handle.stage},target=/workspace,readonly" <> engine.mount_options()

      image = engine.pinned_image(config.image, identity)
      env = Map.merge(Map.put(config.env, "HOME", "/tmp"), Map.get(request, :env, %{}))

      args =
        [
          "--name",
          handle.name,
          "--cap-drop",
          "ALL",
          "--read-only",
          "--user",
          "65534:65534",
          "--memory",
          "1024m",
          "--cpus",
          "2",
          "--workdir",
          cwd,
          "--mount",
          mount,
          "--entrypoint",
          config.binary
        ] ++
          engine.staged_flags() ++
          env_args(env) ++
          network_args(config, handle, request, mode) ++
          [image | config.flags ++ arguments(request)]

      case engine.create(transport, args, @control_ms, watch) do
        {0, _} -> :ok
        {status, output} when is_integer(status) -> {:error, {:launch_failed, output}}
        _ -> {:error, :unknown}
      end
    else
      _ -> {:error, {:launch_failed, "Prepared image or mount changed"}}
    end
  end

  defp arguments(%{probe: args}), do: args
  defp arguments(%{command: command, args: args}), do: ["-c", command, "realm" | args]
  defp arguments(%{entrypoint: script, args: args}), do: ["./" <> script | args]

  defp env_args(env),
    do: Enum.flat_map(Enum.sort(env), fn {key, value} -> ["--env", key <> "=" <> value] end)

  defp network_args(config, _, _, :run), do: config.engine.run_flags()

  defp network_args(config, handle, request, :preview),
    do:
      config.engine.preview_flags(
        config.transport,
        handle.port,
        Map.get(request, :port, @default_port)
      )

  defp now, do: System.monotonic_time(:millisecond)
end
