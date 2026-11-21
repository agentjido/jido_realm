defmodule Jido.Realm.Runner.CLI do
  @moduledoc false

  alias Jido.Realm.Runner

  def run(executable, args, timeout, watch \\ nil, options \\ []) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        :eof,
        args: args
      ])

    deadline = System.monotonic_time(:millisecond) + timeout
    limit = Keyword.get(options, :limit, Runner.output_limit())
    collect(port, watch, deadline, "", limit, options[:on_output])
  rescue
    ArgumentError -> {:unavailable, ""}
    ErlangError -> {:unavailable, ""}
  end

  defp collect(port, watch, deadline, output, limit, on_output) do
    receive do
      {^port, {:data, bytes}} ->
        {chunk, clipped} = Runner.clip(bytes, limit - byte_size(output))
        if on_output, do: on_output.(chunk, clipped)
        next = output <> chunk

        if clipped,
          do: finish_port(port, :output_limit, next),
          else: collect(port, watch, deadline, next, limit, on_output)

      {^port, :eof} ->
        collect(port, watch, deadline, output, limit, on_output)

      {^port, {:exit_status, status}} ->
        finish_port(port, status, output)

      {:DOWN, ^watch, :process, _, _} ->
        finish_port(port, :abandoned, output)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        finish_port(port, :timed_out, output)
    end
  end

  defp finish_port(port, status, output) do
    if Port.info(port), do: Port.close(port)
    {status, output}
  end
end
