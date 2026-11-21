defmodule Jido.Realm.Preview.Native do
  @moduledoc false

  @behaviour Jido.Realm.Preview
  use GenServer

  alias Jido.Realm.{Preview, Runner}

  @start_timeout 1_000
  @stop_timeout 1_500
  @group_timeout 750
  @address {127, 0, 0, 1}

  @impl Preview
  def prepare(_lease, options) do
    with {:ok, options} <- Keyword.validate(options, [:name, :command, :cwd, :port]),
         :ok <- Runner.validate_path(options[:name]),
         [executable | args] = command <- options[:command],
         true <- absolute?(executable) and File.regular?(executable),
         true <- is_list(args) and Enum.all?(args, &is_binary/1),
         true <- absolute?(options[:cwd]) and File.dir?(options[:cwd]),
         port when port in 1..65_535 <- options[:port],
         manager when is_pid(manager) <- Process.whereis(:exec),
         :absent <- probe_group(2_147_483_647) do
      {:ok,
       %{owner: self(), name: options[:name], command: command, cwd: options[:cwd], port: port}}
    else
      _ -> {:error, :native_preview_unavailable}
    end
  end

  @impl Preview
  def start(%{name: name} = config, %{runtime: :native, entrypoint: name} = request) do
    with true <- Map.get(request, :port, config.port) == config.port,
         :ok <- check_request(request),
         :ok <- available_port(config.port),
         {:ok, guardian} <- GenServer.start(__MODULE__, {config, request.id, self()}),
         {:ok, handle} <- get_handle(guardian, request.id) do
      deadline = now() + request.timeout_ms

      case wait_for_ready(handle, config.port, deadline) do
        :ok -> {:ok, handle, %{host: "127.0.0.1", port: config.port}}
        {:error, reason} -> failed_start(config, request.id, handle, reason)
      end
    else
      false -> {:error, :native_service_unavailable}
      error -> error
    end
  end

  def start(_, _), do: {:error, :native_service_unavailable}

  @impl Preview
  def running?(handle), do: Process.alive?(handle.guardian) and Process.alive?(handle.process)

  @impl Preview
  def stop(_config, handle) do
    GenServer.call(handle.guardian, :stop, 2 * @stop_timeout + @group_timeout + 500)
  catch
    :exit, _ -> confirm_stopped(handle)
  end

  @impl GenServer
  def init({config, id, launcher}) do
    Process.flag(:trap_exit, true)
    owner = Process.monitor(config.owner)
    launch = Process.monitor(launcher)

    options = [
      {:group, 0},
      :kill_group,
      {:kill_timeout, 1},
      {:stdin, :close},
      :stdout,
      {:stderr, :stdout},
      {:cd, config.cwd},
      {:env, [:clear, {"HOST", "127.0.0.1"}, {"PORT", Integer.to_string(config.port)}]}
    ]

    case :exec.run_link(config.command, options, @start_timeout) do
      {:ok, process, group} ->
        handle = %{guardian: self(), process: process, group: group}
        {:ok, %{handle: handle, owner: owner, launch: launch, output: ""}}

      {:error, _} ->
        {:stop, :runtime_launch_failed}
    end
  catch
    :exit, _ -> {:stop, {:unknown, id}}
  end

  @impl GenServer
  def handle_call(:handle, _from, state), do: {:reply, state.handle, state}
  def handle_call(:output, _from, state), do: {:reply, state.output, state}

  def handle_call(:stop, _from, state) do
    case stop_group(state.handle) do
      :ok -> {:stop, :normal, :ok, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_info({:stdout, group, bytes}, %{handle: %{group: group}} = state) do
    {chunk, _} = Runner.clip(bytes, Runner.output_limit() - byte_size(state.output))
    {:noreply, %{state | output: state.output <> chunk}}
  end

  def handle_info({:DOWN, owner, :process, _, _}, %{owner: owner} = state),
    do: stop_orphan(state)

  def handle_info({:DOWN, launch, :process, _, reason}, %{launch: launch} = state)
      when reason != :normal,
      do: stop_orphan(state)

  def handle_info(_, state), do: {:noreply, state}

  defp stop_orphan(state) do
    result = stop_group(state.handle)
    reason = if result == :ok, do: :normal, else: :cleanup_unconfirmed
    {:stop, reason, state}
  end

  defp stop_group(handle) do
    if Process.alive?(handle.process) do
      monitor = Process.monitor(handle.process)

      try do
        :exec.stop_and_wait(handle.process, @stop_timeout)
      catch
        :exit, _ -> :unknown
      after
        Process.demonitor(monitor, [:flush])
      end
    end

    confirm_stopped(handle)
  end

  defp confirm_stopped(handle) do
    with :ok <- await_group(handle.group, now() + @group_timeout),
         false <- Process.alive?(handle.process) do
      :ok
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  defp await_group(group, deadline) do
    case probe_group(group) do
      :absent ->
        :ok

      :present ->
        if now() < deadline do
          Process.sleep(20)
          await_group(group, deadline)
        else
          {:error, :cleanup_unconfirmed}
        end

      :unknown ->
        {:error, :cleanup_unconfirmed}
    end
  end

  defp probe_group(group) when is_integer(group) and group > 1 do
    # Signal zero checks the group without signaling any process to exit.
    case System.cmd("/bin/sh", ["-c", ~S(kill -0 "$1"), "group-probe", "-#{group}"],
           env: [{"LC_ALL", "C"}],
           stderr_to_stdout: true
         ) do
      {"", 0} ->
        :present

      {output, 1} ->
        if String.ends_with?(String.trim_trailing(output), "No such process"),
          do: :absent,
          else: :unknown

      _ ->
        :unknown
    end
  rescue
    ErlangError -> :unknown
  end

  defp probe_group(_), do: :unknown

  defp available_port(port) do
    case :gen_tcp.listen(port, ip: @address, reuseaddr: true) do
      {:ok, socket} -> :gen_tcp.close(socket)
      {:error, _} -> {:error, :preview_port_unavailable}
    end
  end

  defp wait_for_ready(handle, port, deadline) do
    cond do
      not running?(handle) ->
        {:error, :service_exited}

      now() >= deadline ->
        {:error, :readiness_timeout}

      Preview.ready?(port) and probe_group(handle.group) == :present and running?(handle) ->
        :ok

      true ->
        Process.sleep(25)
        wait_for_ready(handle, port, deadline)
    end
  end

  defp failed_start(config, id, handle, reason) do
    output = diagnostics(handle)
    failure = {:service_start_failed, %{id: id, reason: reason, output: output}}

    case stop(config, handle) do
      :ok -> {:error, failure}
      {:error, _} -> {:error, {:service_cleanup_unknown, id, failure}, handle}
    end
  end

  defp diagnostics(handle) do
    handle.guardian |> GenServer.call(:output, 500) |> String.replace_invalid("?")
  catch
    :exit, _ -> ""
  end

  defp get_handle(guardian, id) do
    {:ok, GenServer.call(guardian, :handle, @start_timeout)}
  catch
    :exit, _ -> {:error, {:unknown, id}}
  end

  defp check_request(%{args: [], cwd: ".", inputs: inputs}) when inputs in [[], nil], do: :ok
  defp check_request(_), do: {:error, :invalid_native_service_options}

  defp absolute?(value), do: is_binary(value) and Path.type(value) == :absolute
  defp now, do: System.monotonic_time(:millisecond)
end
