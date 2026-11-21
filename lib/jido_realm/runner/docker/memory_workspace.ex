defmodule Jido.Realm.Runner.Docker.MemoryWorkspace do
  @moduledoc false

  alias Jido.Realm.Runner

  @file_budget 1_048_576
  @wire_budget 4 * div(@file_budget + 2, 3) + 4 * 32 + 6

  # The host supplies all paths as arguments. Only file bytes cross stdin.
  # Reserve stdout for the output frames and send the program output to stderr.
  @script ~S"""
  while [ "$1" != -- ]; do
    path=$1
    shift
    IFS= read -r data || exit 125
    mkdir -p -- "${path%/*}" || exit 125
    printf '%s' "$data" | base64 -d > "$path" || exit 125
  done
  shift
  cwd=$1
  shift

  run_program() {
    while [ "$1" != -- ]; do shift; done
    shift
    (cd "$cwd" && "$@" </dev/null) >&2
  }

  printf 'ready\n'
  run_program "$@" || exit "$?"

  for path do
    [ "$path" != -- ] || break
    if [ -f "$path" ] &&
      [ "$(realpath "$path" && printf .)" = "$(printf '/workspace/%s\n.' "${path#./}")" ]; then
      base64 -w 0 -- "$path" || exit 125
      printf '\n'
    else
      printf '!\n'
    fi
  done
  """

  def capture(binding, request, read_bytes) do
    paths = Enum.uniq([request.entrypoint | request.inputs || []])
    roots = Enum.map(paths, &Runner.rooted(request.cwd, &1))
    output_paths = Enum.map(Map.get(request, :outputs, []), &Runner.rooted(request.cwd, &1))

    with {:ok, outputs} <- capture_revisions(binding, output_paths),
         {:ok, stdin} <- capture_bytes(binding, roots, read_bytes) do
      {:ok, %{inputs: roots, outputs: outputs, stdin: stdin}}
    end
  end

  defp capture_revisions(binding, paths) do
    paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, versions} ->
      case Runner.revision(binding, path) do
        {:ok, revision} -> {:cont, {:ok, [{path, revision} | versions]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, versions} -> {:ok, Enum.reverse(versions)}
      error -> error
    end
  end

  defp capture_bytes(binding, paths, read_bytes) do
    paths
    |> Enum.reduce_while({:ok, [], 0}, fn path, {:ok, lines, size} ->
      case read_bytes.(binding, path) do
        {:ok, bytes} ->
          bytes = IO.iodata_to_binary(bytes)
          total = size + byte_size(bytes)

          if total <= @file_budget,
            do: {:cont, {:ok, [[Base.encode64(bytes), "\n"] | lines], total}},
            else: {:halt, {:error, :input_limit}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, lines, _} -> {:ok, lines |> Enum.reverse() |> IO.iodata_to_binary()}
      error -> error
    end
  end

  def command(config, request, workspace) do
    mounts = ["--tmpfs", "/workspace:rw,exec,nosuid,nodev,size=16m,mode=1777"]
    inputs = Enum.map(workspace.inputs, &("./" <> &1))
    outputs = Enum.map(workspace.outputs, fn {path, _} -> "./" <> path end)
    runtime = [config.binary | config.flags] ++ ["./" <> request.entrypoint | request.args]
    args = ["-c", @script, "realm-workspace" | inputs]
    {mounts, "/bin/sh", args ++ ["--", "./" <> request.cwd] ++ outputs ++ ["--" | runtime]}
  end

  def attach(config, request, name, stdin, watch) do
    args = config.prefix ++ ["container", "start", "--attach", "--interactive", name]
    deadline = System.monotonic_time(:millisecond) + request.timeout_ms

    case :exec.run(
           [config.docker | args],
           [:stdin, :stdout, :stderr, :monitor],
           request.timeout_ms
         ) do
      {:ok, pid, os_pid} ->
        try do
          with :ok <- :exec.send(os_pid, stdin),
               :ok <- :exec.send(os_pid, :eof) do
            collect(os_pid, watch, deadline, "", "")
          else
            _ -> {:error, :unknown}
          end
        after
          if Process.alive?(pid), do: :exec.stop(pid)
        end

      {:error, _} ->
        {:error, :runtime_launch_failed}
    end
  catch
    :exit, _ -> {:error, :unknown}
  end

  defp collect(os_pid, watch, deadline, files, output) do
    receive do
      {:stdout, ^os_pid, bytes} ->
        if byte_size(files) + byte_size(bytes) <= @wire_budget,
          do: collect(os_pid, watch, deadline, files <> bytes, output),
          else: {:resource_limit, output}

      {:stderr, ^os_pid, bytes} ->
        {chunk, clipped} = Runner.clip(bytes, Runner.output_limit() - byte_size(output))
        output = output <> chunk

        if clipped,
          do: {:resource_limit, output},
          else: collect(os_pid, watch, deadline, files, output)

      {:DOWN, ^os_pid, :process, _, _} ->
        {:exited, files, output}

      {:DOWN, ^watch, :process, _, _} ->
        {:error, :unknown}
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> {:timed_out, output}
    end
  end

  def publish(binding, outputs, %{status: :succeeded} = result, files) do
    case decode(outputs, :binary.split(files, "\n", [:global]), %{}, 0) do
      {:ok, drafts} -> Runner.publish(drafts, binding, result)
      {:error, path, reason} -> Runner.publication_failed(result, path, reason)
    end
  end

  def publish(_, _, result, _), do: result

  defp decode([], [""], drafts, _), do: {:ok, drafts}

  defp decode([{path, revision} | paths], [line | lines], drafts, size) do
    with {:ok, bytes} <- Base.decode64(line),
         true <- String.valid?(bytes) do
      total = size + byte_size(bytes)

      if total <= @file_budget,
        do: decode(paths, lines, Map.put(drafts, path, {bytes, revision}), total),
        else: {:error, path, :output_limit}
    else
      _ -> {:error, path, :invalid_run_output}
    end
  end

  defp decode(_, _, _, _), do: {:error, nil, :invalid_run_output}
end
