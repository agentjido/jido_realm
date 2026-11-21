defmodule Jido.Realm.Execution do
  @moduledoc false

  alias Jido.Realm.Coding.Request
  alias Jido.Realm.{Commands, Runner}

  def validate(id, mode) do
    cond do
      not (is_binary(id) and byte_size(id) in 1..128) -> {:error, :invalid_request_id}
      mode not in [:sync, :background] -> {:error, :invalid_run_options}
      true -> :ok
    end
  end

  def prepare(_, {:prepared, request}, [], _id, _grants),
    do: {:ok, guest_run(request)}

  def prepare(_, {:entrypoint, runtime, path}, opts, id, _) do
    with {:ok, request} <- Runner.request(runtime, path, opts),
         do: {:ok, guest_run(%{request | id: id})}
  end

  def prepare(state, {:shell, :bash, command}, opts, id, _) do
    with :ok <- allow_shell(state, :bash), do: shell_work(command, opts, id)
  end

  def prepare(state, {:coding, kind, params}, [], id, _) do
    checks = Keyword.get(state.coding, :checks, %{})

    with {:ok, request} <- Request.build(kind, params, id, checks),
         :ok <- allow_shell(state, kind) do
      {:ok, guest_run(request, [Request.control(kind)])}
    end
  end

  def prepare(state, {:command, name, input}, opts, id, grants) do
    with {:ok, options} <- options(opts, [:source_ref]),
         :ok <- command_capability(state),
         {:ok, command} <- Commands.request(state.commands, name, input, grants),
         {:ok, work} <- command_run(state, command, name, input, options, id, grants) do
      request = Map.put(work.request, :command_call, {name, input, options})
      {:ok, %{work | request: request, required: [command.grant | work.required]}}
    end
  end

  def prepare(_, _, _, _, _), do: {:error, :invalid_run_options}

  defp command_run(_, %{run: _} = command, _, input, opts, id, _) when map_size(opts) == 0 do
    {:ok,
     %{
       request: %{id: id, kind: :host_command},
       target: {:host, command, input},
       controls: [],
       required: [:read]
     }}
  end

  defp command_run(_, %{exec: {:check, :bash, script}} = command, name, _, opts, id, _) do
    check = Map.get(command, :options, %{})
    params = Map.put(opts, :name, name)

    with true <- is_map(check),
         {:ok, request} <-
           Request.build(:check, params, id, %{name => Map.put(check, :command, script)}) do
      {:ok, guest_run(request, [:checked_source])}
    else
      false -> {:error, :invalid_run_options}
      error -> error
    end
  end

  defp command_run(_, %{exec: {:check, runtime, path}} = command, name, _, opts, id, _) do
    with {:ok, request} <-
           Request.check_entrypoint(
             runtime,
             path,
             Map.get(command, :options, []),
             name,
             id,
             opts[:source_ref]
           ) do
      {:ok, guest_run(request, [:checked_source])}
    end
  end

  defp command_run(_, %{exec: {:shell, :bash, script}} = command, _, _, opts, id, _)
       when map_size(opts) == 0,
       do: shell_work(script, Map.get(command, :options, []), id)

  defp command_run(state, %{exec: spec} = command, _, _, opts, id, grants)
       when map_size(opts) == 0,
       do: prepare(state, spec, Map.get(command, :options, []), id, grants)

  defp command_run(_, _, _, _, _, _, _), do: {:error, :invalid_run_options}

  defp shell_work(command, opts, id) do
    with {:ok, opts} <- options(opts, [:cwd, :timeout_ms]),
         {:ok, request} <- Request.build(:bash, Map.put(opts, :command, command), id, %{}) do
      {:ok, guest_run(request, [:bash_command])}
    end
  end

  def options(opts, keys) do
    with true <- Keyword.keyword?(opts),
         {:ok, options} <- Keyword.validate(opts, keys) do
      {:ok, Map.new(options)}
    else
      _ -> {:error, :invalid_run_options}
    end
  end

  defp allow_shell(state, :bash) do
    if Keyword.get(state.coding, :bash, false), do: :ok, else: {:error, :permission_denied}
  end

  defp allow_shell(_, _), do: :ok

  defp guest_run(request, controls \\ []) do
    grants =
      if Map.get(request, :outputs, []) == [], do: [:read, :run], else: [:read, :run, :write]

    %{request: request, target: :runner, controls: controls, required: grants}
  end

  def authorize(%{required: required}, grants) do
    if Enum.all?(required, &Runner.allowed?(grants, &1)),
      do: :ok,
      else: {:error, :permission_denied}
  end

  def replay(%{mode: :background, request: %{id: id}}), do: {:ok, %{id: id}}
  def replay(%{reply: reply}), do: reply

  def adapter_request(session_id, max_run_ms, %{timeout_ms: timeout} = request) do
    resource_id =
      :crypto.hash(:sha256, :erlang.term_to_binary({session_id, request.id}))
      |> binary_part(0, 16)
      |> Base.encode16(case: :lower)

    Map.merge(request, %{timeout_ms: min(timeout, max_run_ms), resource_id: resource_id})
  end

  def adapter_request(_, _, request), do: request

  defp command_capability(%{phase: phase, capabilities: capabilities})
       when phase != :new and phase != :closed do
    if :commands in capabilities, do: :ok, else: {:error, :commands_unavailable}
  end

  defp command_capability(_), do: {:error, :session_closed}

  def terminal_status(_entry, {:ok, result}, _id), do: Map.put_new(result, :status, :succeeded)

  def terminal_status(entry, {:error, {:unknown, id}}, id),
    do: %{entry.status | status: :unknown}

  def terminal_status(entry, {:error, reason}, _id),
    do: Map.merge(entry.status, %{status: :failed, error: reason})
end
