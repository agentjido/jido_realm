defmodule Jido.Realm.Runner.Docker do
  @moduledoc """
  Runs Bash, Python, or JavaScript in a fresh Docker container.

  Configure a trusted Docker context and a cached Linux image for each
  runtime. Realm stages the entry point and declared inputs into a private
  read-only tree. The program can use bounded scratch space in `/tmp`.
  Its combined output is bounded. Set `:workspace` to `:memory` to load
  declared inputs into container tmpfs and save declared outputs with
  checked Realm writes after a successful run.
  """

  @behaviour Jido.Realm.Runner
  @behaviour Jido.Realm.Preview

  alias Jido.Realm.{Files, Preview, Runner}
  alias Jido.Realm.Runner.Docker.{Engine, MemoryWorkspace}
  alias Jido.Realm.Runner.Staged

  @interpreter %{
    bash: {"/usr/local/bin/bash", ["--noprofile", "--norc"]},
    python: {"/usr/local/bin/python3", ["-B"]},
    javascript: {"/usr/local/bin/node", []}
  }
  @control_timeout 3_000
  @input_limit 1_048_576
  @preview_port 8080

  @impl Jido.Realm.Runner
  def prepare(runtime, lease, staged: options),
    do: Staged.prepare(Engine, runtime, lease, options)

  def prepare(runtime, %{binding: binding}, opts) when is_map_key(@interpreter, runtime) do
    {default_binary, flags} = Map.fetch!(@interpreter, runtime)

    with {:ok, options} <-
           Keyword.validate(opts, [
             :image,
             context: nil,
             binary: default_binary,
             private_network: nil,
             workspace: :read_only
           ]),
         workspace when workspace in [:read_only, :memory] <- options[:workspace],
         image when is_binary(image) and image != "" <- options[:image],
         binary when is_binary(binary) <- options[:binary],
         :absolute <- Path.type(binary),
         {:ok, transport} <- Engine.connect(options),
         {:ok, run_network} <- private_network(transport, options[:private_network]),
         {:ok, id} <- Engine.image_identity(transport, image) do
      {:ok,
       Map.merge(transport, %{
         binding: binding,
         image: id,
         run_network: run_network,
         binary: binary,
         flags: flags,
         workspace: workspace
       })}
    else
      _ -> {:error, :runtime_unavailable}
    end
  end

  def prepare(_, _, _), do: {:error, :unsupported_runtime}

  @impl Jido.Realm.Preview
  def prepare(lease, staged: options), do: Staged.prepare_service(Engine, lease, options)

  def prepare(lease, opts) do
    with {:ok, opts} <- Keyword.validate(opts, [:runtime, :runner, :network]),
         network when is_binary(network) and network not in ["", "host", "none"] <- opts[:network],
         false <- String.starts_with?(network, "container:"),
         {:ok, config} <- prepare(opts[:runtime], lease, opts[:runner]) do
      {:ok,
       Map.merge(config, %{runtime: opts[:runtime], network: network, workspace: :read_only})}
    else
      _ -> {:error, :preview_unavailable}
    end
  end

  @impl Jido.Realm.Preview
  def start(%{engine: Engine} = config, request), do: Staged.start(config, request)

  def start(%{runtime: runtime} = config, %{runtime: runtime} = request) do
    name = "jido-realm-preview-" <> request.id
    handle = %{name: name, stage: Path.join(System.tmp_dir!(), name)}

    with :ok <- File.mkdir(handle.stage) do
      case launch_preview(config, request, handle) do
        {:ok, target} ->
          {:ok, Map.put(handle, :transport, config), target}

        {:error, reason} ->
          case stop(config, handle) do
            :ok -> {:error, reason}
            {:error, _} -> {:error, {:service_cleanup_unknown, request.id, reason}, handle}
          end
      end
    else
      {:error, _} -> {:error, :backend_error}
    end
  end

  def start(_, _), do: {:error, :unsupported_runtime}

  @impl Jido.Realm.Preview
  def stop(%{engine: Engine} = config, handle), do: Staged.stop(config, handle)

  def stop(config, handle) do
    if Engine.remove(config, handle.name) == :ok or Engine.absent?(config, handle.name) do
      remove_stage(handle.stage)
    else
      {:error, :unknown}
    end
  end

  @impl Jido.Realm.Preview
  def verified_source?(config), do: match?(%{engine: Engine}, config)

  @impl Jido.Realm.Preview
  def running?(%{engine: Engine} = handle), do: Staged.running?(handle)
  def running?(handle), do: Engine.running?(handle.transport, handle.name)

  @doc false
  def reconcile(%{engine: Engine} = config, request), do: Staged.reconcile(config, request)

  def reconcile(config, request) do
    name = "jido-realm-" <> Map.get(request, :resource_id, request.id)
    stop(config, %{name: name, stage: Path.join(System.tmp_dir!(), name)})
  end

  defp remove_stage(stage) do
    case File.rm_rf(stage) do
      {:ok, _} -> :ok
      {:error, _, _} -> {:error, :backend_error}
    end
  end

  defp launch_preview(config, request, handle) do
    guest_port = Map.get(request, :port, @preview_port)

    with :ok <- prepare_stage(config, request, handle.stage),
         :ok <-
           create(config, request, handle.stage, workdir(request), handle.name, nil, :preview),
         {0, _} <- Engine.boot(config, handle.name),
         {:ok, port} <- Engine.published_port(config, handle.name, guest_port, nil),
         :ok <- wait_until_ready(config, handle.name, port, now() + request.timeout_ms) do
      {:ok, %{host: "127.0.0.1", port: port}}
    else
      failure ->
        reason =
          if match?({:error, _}, failure), do: elem(failure, 1), else: :runtime_launch_failed

        output = Engine.logs(config, handle.name)

        {:error,
         {:service_start_failed,
          %{id: request.id, reason: reason, output: String.replace_invalid(output)}}}
    end
  end

  defp wait_until_ready(config, name, port, deadline) do
    cond do
      now() >= deadline ->
        {:error, :readiness_timeout}

      Preview.ready?(port) ->
        :ok

      not Engine.running?(config, name) ->
        {:error, :service_exited}

      true ->
        Process.sleep(40)
        wait_until_ready(config, name, port, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  @impl Jido.Realm.Runner
  def controls(%{engine: Engine} = config), do: Staged.controls(config)

  def controls(config) do
    network = if config.run_network == "none", do: :loopback_only, else: :private_network
    common = [:private_scratch, network, :non_root]

    if config.workspace == :memory,
      do: [:memory_workspace, :declared_outputs | common],
      else: [:read_only_inputs | common]
  end

  defp private_network(_, nil), do: {:ok, "none"}

  defp private_network(config, name) when is_binary(name) do
    args = ["network", "inspect", "--format", "{{.Id}} {{.Driver}} {{.Internal}}", "--", name]

    with {0, result} <- Engine.command(config, args),
         [id, "bridge", "true"] <- String.split(result),
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, id) do
      {:ok, id}
    else
      _ -> {:error, :private_network_unavailable}
    end
  end

  defp private_network(_, _), do: {:error, :private_network_unavailable}

  @impl Jido.Realm.Runner
  def execute(%{engine: Engine} = config, request, grants),
    do: Staged.execute(config, request, grants)

  def execute(config, request, _grants) do
    owner = self()
    ref = make_ref()

    {worker, monitor} =
      spawn_monitor(fn ->
        # Keep cleanup alive if the Session stops waiting during Docker I/O.
        watch = Process.monitor(owner)

        result =
          case config.workspace do
            :memory -> memory_run(config, request, watch)
            :read_only -> staged_run(config, request, watch)
          end

        send(owner, {ref, result})
      end)

    receive do
      {^ref, {:ok, result, outputs, files}} ->
        Process.demonitor(monitor, [:flush])
        {:ok, MemoryWorkspace.publish(config.binding, outputs, result, files)}

      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^worker, _} ->
        {:error, :unknown}
    end
  end

  defp memory_run(config, request, watch) do
    name = "jido-realm-" <> Map.get(request, :resource_id, request.id)

    with {:ok, workspace} <- MemoryWorkspace.capture(config.binding, request, &stage_bytes/2),
         :ok <- create(config, request, workspace, "/workspace", name, watch, :memory) do
      attached = MemoryWorkspace.attach(config, request, name, workspace.stdin, watch)

      result =
        case attached do
          {:timed_out, output} ->
            {:ok, Runner.result(:timed_out, nil, output)}

          {:resource_limit, output} ->
            {:ok, Runner.result(:resource_limit, nil, output, true)}

          {:exited, "ready\n" <> files, output} ->
            with {:ok, result} <- exit_result(config, name, output), do: {:ok, result, files}

          {:exited, _, _} ->
            {:error, :runtime_launch_failed}

          {:error, _} = error ->
            error
        end

      with :ok <- Engine.remove(config, name) do
        case result do
          {:ok, result, files} ->
            {:ok, result, workspace.outputs, files}

          terminal ->
            terminal
        end
      end
    end
  end

  defp staged_run(config, request, watch) do
    name = "jido-realm-" <> Map.get(request, :resource_id, request.id)
    stage = Path.join(System.tmp_dir!(), name)

    with :ok <- File.mkdir(stage) do
      try do
        with :ok <- prepare_stage(config, request, stage),
             :ok <- create(config, request, stage, workdir(request), name, watch, :run) do
          result = start(config, request, name, watch)
          if Engine.remove(config, name) == :ok, do: result, else: {:error, :unknown}
        end
      after
        File.rm_rf(stage)
      end
    else
      {:error, _} -> {:error, :backend_error}
    end
  end

  defp workdir(%{cwd: "."}), do: "/workspace"
  defp workdir(%{cwd: cwd}), do: "/workspace/" <> cwd

  defp prepare_stage(config, request, stage) do
    with :ok <- File.chmod(stage, 0o755),
         :ok <- copy_inputs(config.binding, request, stage),
         do: valid_mount(stage)
  end

  defp copy_inputs(binding, request, stage) do
    paths = Enum.uniq([request.entrypoint | request.inputs || []])

    Enum.reduce_while(paths, :ok, fn relative, :ok ->
      path = Runner.rooted(request.cwd, relative)
      file = Path.join(stage, path)

      with {:ok, bytes} <- stage_bytes(binding, path),
           :ok <- stage_file(stage, file, bytes) do
        {:cont, :ok}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp stage_bytes(binding, path) do
    case Files.execute(binding, :consume, path, {65_536, &bounded_bytes/1}) do
      {:error, :unsupported_file_operation} ->
        case Files.execute(binding, :read, path, nil) do
          {:ok, %{content: bytes}} when byte_size(bytes) <= @input_limit -> {:ok, bytes}
          {:ok, _} -> {:error, :input_limit}
          {:error, _} = error -> error
        end

      result ->
        result
    end
  end

  defp bounded_bytes(chunks) do
    case Enum.reduce_while(chunks, {0, []}, fn chunk, {size, parts} ->
           if size + byte_size(chunk) <= @input_limit do
             {:cont, {size + byte_size(chunk), [chunk | parts]}}
           else
             {:halt, :limit}
           end
         end) do
      {_, parts} -> {:ok, Enum.reverse(parts)}
      :limit -> {:error, :input_limit}
    end
  rescue
    File.Error -> {:error, :backend_error}
  end

  defp stage_file(stage, file, bytes) do
    directory = Path.dirname(file)

    with :ok <- File.mkdir_p(directory),
         :ok <- share_directories(stage, directory),
         :ok <- File.write(file, bytes, [:exclusive]),
         :ok <- File.chmod(file, 0o644) do
      :ok
    else
      {:error, _} -> {:error, :backend_error}
    end
  end

  defp share_directories(stage, stage), do: :ok

  defp share_directories(stage, directory) do
    with :ok <- File.chmod(directory, 0o755),
         do: share_directories(stage, Path.dirname(directory))
  end

  defp valid_mount(path) do
    if String.contains?(path, [",", "\""]), do: {:error, :invalid_runtime_mount}, else: :ok
  end

  defp create(config, request, workspace, cwd, name, watch, mode) do
    {workspace_flags, entrypoint, command} = container_command(config, request, workspace, mode)

    args =
      [
        "--name",
        name,
        "--pull=never",
        "--ipc=none",
        "--read-only",
        "--cap-drop=ALL",
        "--security-opt=no-new-privileges=true",
        "--user=65534:65534",
        "--pids-limit=64",
        "--cpus=1",
        "--memory=128m",
        "--memory-swap=128m",
        "--no-healthcheck",
        "--tmpfs",
        "/tmp:rw,nosuid,nodev,noexec,size=16m,mode=1777"
      ] ++
        workspace_flags ++
        [
          "--workdir",
          cwd,
          "--entrypoint",
          entrypoint
        ] ++
        mode_flags(config, request, mode) ++
        [config.image | command]

    case Engine.create(config, args, @control_timeout, watch) do
      {0, _} ->
        :ok

      _ when mode == :preview ->
        {:error, :runtime_launch_failed}

      {status, _} ->
        # An interrupted create request can still be in flight when ls runs.
        if Engine.remove(config, name) == :ok or
             (is_integer(status) and Engine.absent?(config, name)) do
          {:error, :runtime_launch_failed}
        else
          {:error, :unknown}
        end
    end
  end

  defp container_command(config, request, workspace, :memory),
    do: MemoryWorkspace.command(config, request, workspace)

  defp container_command(config, request, stage, _) do
    mount = "type=bind,source=#{stage},target=/workspace,readonly,bind-recursive=disabled"

    {["--mount", mount], config.binary,
     config.flags ++ ["./" <> request.entrypoint | request.args]}
  end

  defp mode_flags(config, request, :memory),
    do: ["--interactive" | mode_flags(config, request, :run)]

  defp mode_flags(config, _request, :run),
    do: ["--label=io.jido.realm.run=true", "--network", config.run_network, "--log-driver=none"]

  defp mode_flags(config, request, :preview),
    do: [
      "--label=io.jido.realm.preview=true"
      | Engine.preview_flags(config, nil, Map.get(request, :port, @preview_port))
    ]

  defp start(config, request, name, watch) do
    case Engine.attach(config, name, request.timeout_ms, watch) do
      {:timed_out, output} -> {:ok, Runner.result(:timed_out, nil, output)}
      {:output_limit, output} -> {:ok, Runner.result(:resource_limit, nil, output, true)}
      {:abandoned, _} -> {:error, :unknown}
      {status, output} when is_integer(status) -> exit_result(config, name, output)
      _ -> {:error, :unknown}
    end
  end

  defp exit_result(config, name, output) do
    args = ["container", "inspect", "--format", "{{.State.Status}} {{.State.ExitCode}}", name]

    case Engine.command(config, args) do
      {0, "created " <> _} ->
        {:error, :runtime_launch_failed}

      {0, "exited " <> code} ->
        case Integer.parse(String.trim(code)) do
          {exit_code, ""} when exit_code >= 0 ->
            status = if exit_code == 0, do: :succeeded, else: :failed
            {:ok, Runner.result(status, exit_code, output)}

          _ ->
            {:error, :unknown}
        end

      _ ->
        {:error, :unknown}
    end
  end
end
