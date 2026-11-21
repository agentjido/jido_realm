defmodule Jido.Realm.Runner.Lua do
  @moduledoc """
  Runs each program in a fresh Lua VM on the BEAM.

  The program accesses files through `realm.read(path)` and
  `realm.write(path, text)`. A successful evaluation publishes its drafts
  in path order using checked writes. A failed evaluation publishes no drafts.
  Publication is per file.
  """

  @behaviour Jido.Realm.Runner

  alias Jido.Realm.{Files, Runner}

  @file_limit 65_536
  @heap_words 2_000_000
  @draft_limit 16
  @output_key {__MODULE__, :output}
  @report_key {__MODULE__, :report}

  @impl true
  def prepare(:lua, %{binding: binding, capabilities: %{files: true, revisions: true}}, []),
    do: {:ok, binding}

  def prepare(_, _, _), do: {:error, :unsupported_runtime}

  @impl true
  def controls(_binding), do: [:bounded_progress]

  @impl true
  def execute(binding, request, grants) do
    entrypoint = Runner.rooted(request.cwd, request.entrypoint)

    with {:ok, source} <- read(binding, entrypoint) do
      case evaluate(source, binding, request, grants) do
        {:ok, drafts, result} -> {:ok, Runner.publish(drafts, binding, result)}
        {:finished, result} -> {:ok, result}
      end
    end
  end

  defp evaluate(source, binding, request, grants) do
    parent = self()
    ref = make_ref()
    previous = Process.flag(:trap_exit, true)

    {pid, monitor} =
      :erlang.spawn_opt(
        fn -> send(parent, {ref, eval(source, binding, request, grants)}) end,
        [
          :link,
          :monitor,
          {:max_heap_size,
           %{size: @heap_words, kill: true, error_logger: false, include_shared_binaries: true}}
        ]
      )

    try do
      receive do
        {^ref, result} ->
          result

        {:DOWN, ^monitor, :process, ^pid, :killed} ->
          {:finished, Runner.result(:resource_limit, nil, "Lua memory limit exceeded")}

        {:DOWN, ^monitor, :process, ^pid, _} ->
          {:finished, Runner.result(:failed, nil, "Lua evaluation stopped unexpectedly")}

        {:EXIT, sender, reason} when sender != pid ->
          stop(pid, monitor)
          exit(reason)
      after
        request.timeout_ms ->
          stop(pid, monitor)
          {:finished, Runner.result(:timed_out, nil)}
      end
    after
      Process.unlink(pid)
      Process.demonitor(monitor, [:flush])
      Process.flag(:trap_exit, previous)
    end
  end

  defp stop(pid, monitor) do
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    end
  end

  defp eval(source, binding, request, grants) do
    Process.put(@output_key, {"", false})
    Process.put(@report_key, Map.get(request, :on_output))

    lua =
      Lua.new(
        exclude: [[:load]],
        max_call_depth: 64,
        max_string_bytes: @file_limit,
        max_instructions: 1_000_000
      )
      |> Lua.set!(:io, nil)
      |> Lua.set!(:os, nil)
      |> Lua.set!(:debug, nil)
      |> Lua.set!(:package, nil)
      |> Lua.set!(
        :arg,
        Map.new(Enum.with_index([request.entrypoint | request.args]), fn {value, idx} ->
          {idx, value}
        end)
      )
      |> Lua.set!(:print, &print/2)
      |> Lua.set!([:realm, :read], &lua_read(&1, &2, binding, request))
      |> Lua.set!([:realm, :write], &lua_write(&1, &2, binding, request, grants))
      |> Lua.put_private(:drafts, %{})

    {_, lua} = Lua.eval!(lua, source, decode: false)
    {:ok, Lua.get_private!(lua, :drafts), result(:succeeded, 0)}
  rescue
    error in [Lua.CompilerException, Lua.RuntimeException] ->
      append(Exception.message(error))
      {:finished, result(:failed, 1)}
  end

  defp lua_read([path], lua, binding, request) do
    with :ok <- Runner.validate_path(path),
         rooted = Runner.rooted(request.cwd, path),
         {:ok, bytes} <- read_path(lua, binding, rooted, path, request) do
      [bytes]
    else
      {:error, reason} -> {:error, "Realm read failed: #{reason}", lua}
    end
  end

  defp lua_read(_, lua, _binding, _request), do: {:error, "Realm read requires a path", lua}

  defp read_path(lua, binding, rooted, path, request) do
    case Map.fetch(Lua.get_private!(lua, :drafts), rooted) do
      {:ok, {bytes, _}} ->
        {:ok, bytes}

      :error ->
        if request.inputs == nil or path == request.entrypoint or path in request.inputs,
          do: read(binding, rooted),
          else: {:error, :permission_denied}
    end
  end

  defp lua_write([path, bytes], lua, binding, request, grants) when is_binary(bytes) do
    with true <- Runner.allowed?(grants, :write),
         :ok <- Runner.validate_path(path),
         true <- byte_size(bytes) <= @file_limit and String.valid?(bytes),
         {:ok, drafts} <- stage(lua, binding, Runner.rooted(request.cwd, path), bytes) do
      {[true], Lua.put_private(lua, :drafts, drafts)}
    else
      false -> {:error, "Realm write denied or exceeds the file limit", lua}
      {:error, reason} -> {:error, "Realm write failed: #{reason}", lua}
    end
  end

  defp lua_write(_, lua, _binding, _request, _grants),
    do: {:error, "Realm write requires a path and text", lua}

  defp stage(lua, binding, path, bytes) do
    drafts = Lua.get_private!(lua, :drafts)

    with {:ok, revision} <- revision(drafts, binding, path) do
      next = Map.put(drafts, path, {bytes, revision})
      size = Enum.sum_by(next, fn {_, {text, _}} -> byte_size(text) end)

      if map_size(next) <= @draft_limit and size <= @file_limit,
        do: {:ok, next},
        else: {:error, :draft_limit}
    end
  end

  defp revision(drafts, binding, path) do
    case Map.fetch(drafts, path) do
      {:ok, {_, revision}} ->
        {:ok, revision}

      :error ->
        Runner.revision(binding, path)
    end
  end

  defp read(binding, path) do
    case Files.execute(binding, :read, path, nil) do
      {:ok, %{content: bytes}} when byte_size(bytes) <= @file_limit -> {:ok, bytes}
      {:ok, _} -> {:error, :input_limit}
      {:error, _} = error -> error
    end
  end

  defp print(args, _lua) do
    Enum.each(Enum.intersperse(args, "\t"), &append(printable(&1)))
    append("\n")
    []
  end

  defp printable(value) when is_binary(value), do: value
  defp printable(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp printable(nil), do: "nil"
  defp printable(_), do: "<value>"

  defp append(bytes) do
    {output, truncated} = Process.get(@output_key)
    {chunk, clipped} = Runner.clip(bytes, Runner.output_limit() - byte_size(output))
    Process.put(@output_key, {output <> chunk, truncated or clipped})

    if chunk != "" or (clipped and not truncated) do
      if report = Process.get(@report_key), do: report.(chunk, clipped)
    end
  end

  defp result(status, exit_code) do
    {output, truncated} = Process.get(@output_key)
    Runner.result(status, exit_code, output, truncated)
  end
end
