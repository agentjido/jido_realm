defmodule Jido.Realm.Session do
  @moduledoc """
  Owns an opened Realm's placement and drains admitted operations on close.

  If the host supplies an owner process, its exit starts the same drain.
  A supervisor shutdown waits briefly for active operations. A provider
  lease that cannot be released safely may require host recovery.
  The host can select runners and cap their execution time with `:max_run_ms`.
  """

  use GenServer, restart: :temporary

  alias Jido.Realm.Coding.Request
  alias Jido.Realm.{Commands, Execution, Files, Preview, Profile, Runner, Service}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def open(session, profile \\ :configured), do: call(session, {:open, profile}, :unknown)
  def close(session, profile \\ :configured), do: call(session, {:close, profile}, :unknown)

  @doc false
  def save(session, profile, verified_by),
    do: call(session, {:save, profile, verified_by}, :unknown)

  @doc false
  def file(session, profile, operation, path, input) do
    call(session, {:file, profile, operation, path, input}, interrupted(operation))
  end

  @doc false
  def execute(session, profile, spec, opts, grants) do
    {id, options} = Keyword.pop(opts, :request_id)
    generated = if Keyword.has_key?(opts, :request_id), do: id, else: new_id()

    call(
      session,
      {:execute, profile, spec, options, generated, Keyword.has_key?(opts, :request_id), grants},
      {:unknown, generated}
    )
  end

  @doc false
  def run(session, profile, request, grants),
    do: execute(session, profile, {:prepared, request}, [request_id: request.id], grants)

  @doc false
  def coding_run(session, profile, kind, params, id, grants),
    do: execute(session, profile, {:coding, kind, params}, [request_id: id], grants)

  @doc "Confirms cleanup of an unresolved coding request. Only the session owner can call this."
  def reconcile_run(session, id), do: call(session, {:reconcile_run, id}, {:unknown, id})

  @doc false
  def start_checked_preview(session, profile, name, source_ref),
    do: call(session, {:checked_preview, profile, name, source_ref}, :unknown)

  @doc false
  def run_status(session, profile, id, grants \\ :all),
    do: call(session, {:run_status, profile, id, grants}, :backend_error)

  @doc false
  def service(session, profile, operation),
    do: call(session, {:service, profile, operation}, :unknown)

  @doc false
  def start_preview(session, profile, request),
    do: call(session, {:start_preview, profile, request}, {:unknown, request.id})

  @doc false
  def stop_preview(session, profile, id),
    do: call(session, {:stop_preview, profile, id}, :unknown)

  @doc false
  def preview_target(session, id, access),
    do: call(session, {:preview_target, id, access}, :not_found)

  @doc false
  def preview_access(session, profile, request),
    do: call(session, {:preview_access, profile, request}, :unknown)

  @doc false
  def commands(session, profile, grants),
    do: call(session, {:commands, profile, grants}, :backend_error)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {provider, options} = Keyword.fetch!(opts, :provider)
    owner = Keyword.get(opts, :owner)

    {:ok,
     %{
       id: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
       profile: Keyword.get(opts, :profile),
       owner: if(owner, do: {owner, Process.monitor(owner)}),
       permitted: Keyword.get(opts, :capabilities, :all),
       preview_options:
         Keyword.take(opts, [
           :preview,
           :preview_base_url,
           :preview_viewers,
           :preview_public_base_url,
           :preview_max_public_ms
         ]),
       preview: nil,
       service: nil,
       services: Service.prepare(Keyword.get(opts, :services, %{})),
       coding: Keyword.get(opts, :coding, []),
       runs: %{},
       max_requests:
         Keyword.get(opts, :max_requests, Keyword.get(opts, :max_coding_requests, 128)),
       commands: Commands.prepare(Keyword.get(opts, :commands, %{})),
       provider: provider,
       options: options,
       runners: Keyword.get(opts, :runners, %{}),
       max_run_ms: Keyword.get(opts, :max_run_ms, 20_000),
       phase: :new,
       lease: nil,
       capabilities: [],
       workers: %{}
     }}
  end

  @impl true
  def handle_call({:open, requested}, _from, state) do
    with :ok <- check_owner(state),
         {:ok, profile} <- check_profile(state, requested) do
      open_placement(state, profile)
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:close, requested}, _from, state) do
    case check_profile(state, requested) do
      {:ok, _} ->
        {reply, state} = close_session(state)
        {:reply, reply, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:file, requested, operation, path, input}, from, state) do
    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested),
         :ok <- admit_file(state, operation),
         :ok <- shared_tree_idle(state),
         :ok <- coding_path(state, operation, path) do
      binding = state.lease.binding

      start_operation(state, from, operation, fn ->
        Files.execute(binding, operation, path, input)
      end)
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:save, requested, verified_by}, from, state) do
    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested),
         :ok <- admit_save(state),
         :ok <- shared_tree_idle(state),
         {:ok, verified_tree} <- checked_tree(state, verified_by) do
      start_operation(state, from, :save, fn ->
        state.provider.save(state.lease, verified_tree)
      end)
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:execute, requested, spec, opts, id, pinned?, grants}, from, state) do
    {mode, opts} = Keyword.pop(opts, :mode, :sync)

    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested),
         :ok <- Execution.validate(id, mode),
         {:ok, work} <- Execution.prepare(state, spec, opts, id, grants),
         work = require_runner_grants(state, work),
         :ok <- Execution.authorize(work, grants) do
      fingerprint = {Map.delete(work.request, :id), mode}
      pinned? = pinned? or work.request[:kind] == :check or match?({:coding, _, _}, spec)

      case Map.fetch(state.runs, work.request.id) do
        {:ok, %{fingerprint: ^fingerprint} = stored} ->
          {:reply, Execution.replay(stored), state}

        {:ok, _} ->
          {:reply, {:error, :request_conflict}, state}

        :error ->
          admit_execution(state, from, work, mode, fingerprint, pinned?, grants)
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:reconcile_run, id}, {caller, _}, %{owner: {caller, _}} = state) do
    with {:uncertain, ^id} <- state.phase,
         %{request: request, runner: {module, adapter}} = stored <- state.runs[id],
         true <- function_exported?(module, :reconcile, 2),
         :ok <- module.reconcile(adapter, request) do
      result = %{id: id, status: :stopped}
      state = put_in(state.runs[id], %{stored | reply: {:ok, result}, status: result})
      {:reply, {:ok, result}, %{state | phase: :open}}
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :reconcile_unavailable}, state}
    end
  end

  def handle_call({:reconcile_run, _}, _from, state),
    do: {:reply, {:error, :permission_denied}, state}

  def handle_call({:checked_preview, requested, name, source_ref}, from, state) do
    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested),
         :ok <- admit_preview(state),
         true <- made_successful_check?(state, source_ref),
         {:ok, command} <- Map.fetch(Keyword.get(state.coding, :services, %{}), name) do
      %{module: module, state: adapter} = state.preview
      id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

      request = %{
        id: id,
        kind: :checked_preview,
        runtime: :bash,
        command: command,
        cwd: ".",
        args: [],
        source_ref: source_ref,
        timeout_ms: 30_000
      }

      start_operation(state, from, {:preview, id}, fn -> module.start(adapter, request) end)
    else
      false -> {:reply, {:error, :unchecked_source}, state}
      :error -> {:reply, {:error, :unknown_service}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:run_status, requested, id, grants}, _from, state) do
    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested),
         true <- state.phase != :closed,
         {:ok, entry} <- Map.fetch(state.runs, id),
         :ok <- Execution.authorize(entry, grants) do
      status =
        case entry.status do
          %{output: output} = status -> %{status | output: String.replace_invalid(output, "?")}
          status -> status
        end

      {:reply, {:ok, status}, state}
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:service, requested, operation}, from, state) do
    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested) do
      service_operation(state, from, operation)
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:start_preview, requested, request}, from, state) do
    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested),
         :ok <- admit_preview(state) do
      %{module: module, state: adapter} = state.preview
      request = %{request | timeout_ms: min(request.timeout_ms, state.max_run_ms)}

      start_operation(state, from, {:preview, request.id}, fn ->
        module.start(adapter, request)
      end)
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:stop_preview, requested, id}, _from, state) do
    with :ok <- check_owner(state), {:ok, _} <- check_profile(state, requested) do
      case state.service do
        %{id: ^id, port_name: nil} ->
          {reply, state} = stop_service(state)
          {:reply, reply, state}

        _ ->
          {:reply, {:error, :not_found}, state}
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:preview_target, id, access}, _from, state) do
    with %{phase: :open, service: %{target: target} = service} <- state,
         true <- not is_nil(target) and accessible?(service, state.preview, id, access),
         true <- Preview.running?(state.preview, service.handle),
         :ok <- check_owner(state) do
      {:reply, {:ok, target}, state}
    else
      _ -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:preview_access, requested, request}, _from, state) do
    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested),
         true <- state.phase == :open do
      {result, state} = update_sharing(state, request)
      {:reply, result, state}
    else
      false -> {:reply, {:error, :session_closed}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:commands, requested, grants}, _from, state) do
    with :ok <- check_owner(state),
         {:ok, _} <- check_profile(state, requested),
         :ok <- admit_commands(state) do
      {:reply, {:ok, Commands.available(state.commands, grants)}, state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp accessible?(%{private: %{id: id}}, preview, id, {:private, viewer}),
    do: MapSet.member?(preview.viewers, viewer)

  defp accessible?(%{public: %{id: id, expires: expiry}}, _preview, id, :public),
    do: expiry > System.monotonic_time(:millisecond)

  defp accessible?(_, _, _, _), do: false

  defp update_sharing(
         %{
           service: %{id: id, port_name: nil, target: target, handle: handle},
           preview: %{sharing: _}
         } =
           state,
         {:share, id, ttl}
       )
       when not is_nil(target) do
    with true <- Preview.running?(state.preview, handle),
         {:ok, route} <-
           Service.endpoint(state.service, state.preview, access: :public, ttl_ms: ttl) do
      {{:ok, Map.take(route, [:id, :url])}, put_in(state.service.public, route)}
    else
      false -> {{:error, :not_found}, state}
      {:error, _} = error -> {error, state}
    end
  end

  defp update_sharing(%{service: %{id: id, port_name: nil}} = state, {:unshare, id}),
    do: {:ok, put_in(state.service.public, nil)}

  defp update_sharing(state, _), do: {{:error, :not_found}, state}

  defp service_operation(state, from, {:start, name, opts}) do
    with :ok <- admit_service(state, :services),
         :ok <- free_service_slot(state),
         {:ok, config} <- Service.fetch(state.services, name),
         {:ok, opts} <- Execution.options(opts, [:verified_by]),
         {:ok, source_ref} <- verified_source(state, config, opts[:verified_by]),
         :ok <- Preview.verify_source(state.preview, source_ref),
         {:ok, request} <- Service.request(config, source_ref, state.max_run_ms) do
      %{module: module, state: adapter} = state.preview

      start_operation(state, from, {:service, request.id, config.port_name}, fn ->
        module.start(adapter, request)
      end)
    else
      {:error, :preview_in_progress} -> {:reply, {:error, :service_in_progress}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp service_operation(%{service: %{id: id, port_name: name}} = state, _, {:stop, id})
       when not is_nil(name) do
    {reply, state} = stop_service(state)
    {:reply, reply, state}
  end

  defp service_operation(state, _, {:expose, service_id, name, opts}) do
    with :ok <- admit_service(state, :ports),
         %{id: ^service_id, port_name: ^name} = service when not is_nil(name) <- state.service,
         true <- Preview.running?(state.preview, service.handle),
         {:ok, endpoint} <- Service.endpoint(service, state.preview, opts) do
      access = opts[:access]
      result = Map.take(endpoint, [:id, :url])
      {:reply, {:ok, result}, put_in(state.service[access], endpoint)}
    else
      {:error, _} = error -> {:reply, error, state}
      _ -> {:reply, {:error, :not_found}, state}
    end
  end

  defp service_operation(
         %{service: %{port_name: name} = service} = state,
         _,
         {:close_port, id, grants}
       )
       when not is_nil(name) do
    case service do
      %{private: %{id: ^id}} ->
        {:reply, :ok, put_in(state.service.private, nil)}

      %{public: %{id: ^id}} ->
        if Runner.allowed?(grants, :publish_preview) do
          {:reply, :ok, put_in(state.service.public, nil)}
        else
          {:reply, {:error, :permission_denied}, state}
        end

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  defp service_operation(state, _, _), do: {:reply, {:error, :not_found}, state}

  defp admit_service(%{phase: :open, capabilities: capabilities}, capability) do
    if capability in capabilities, do: :ok, else: {:error, :service_unavailable}
  end

  defp admit_service(_, _), do: {:error, :session_closed}

  defp verified_source(_, %{require_check: nil}, nil), do: {:ok, nil}

  defp verified_source(state, %{require_check: required}, id) when is_binary(id) do
    case state.runs[id] do
      %{request: %{kind: :check, check: name}, reply: {:ok, result}}
      when required in [nil, name] ->
        case result do
          %{status: :succeeded, source_ref: source} when is_binary(source) -> {:ok, source}
          _ -> {:error, :unchecked_source}
        end

      _ ->
        {:error, :unchecked_source}
    end
  end

  defp verified_source(_, _, _), do: {:error, :unchecked_source}

  defp checked_tree(_, nil), do: {:ok, nil}

  defp checked_tree(state, id) do
    case state.runs[id] do
      %{
        request: %{kind: :check},
        reply: {:ok, %{status: :succeeded, tree_revision: revision}}
      }
      when is_binary(revision) ->
        {:ok, revision}

      _ ->
        {:error, :unchecked_source}
    end
  end

  defp admit_save(%{phase: :open, capabilities: capabilities, provider: provider}) do
    if :snapshots in capabilities and function_exported?(provider, :save, 2),
      do: :ok,
      else: {:error, :snapshot_unavailable}
  end

  defp admit_save(_), do: {:error, :session_closed}

  defp shared_tree_idle(%{lease: %{shared_tree: true}, workers: workers})
       when map_size(workers) > 0,
       do: {:error, :busy}

  defp shared_tree_idle(_), do: :ok

  defp require_runner_grants(%{lease: %{runners: runners}}, %{target: :runner} = work) do
    case runners[work.request.runtime] do
      {module, adapter} ->
        if Runner.provides_controls?(module, adapter, [:writable_tree]),
          do: %{work | required: [:write | work.required]},
          else: work

      nil ->
        work
    end
  end

  defp require_runner_grants(_, work), do: work

  defp open_placement(%{phase: :new} = state, profile) do
    case state.provider.open(state.options) do
      {:ok, lease} ->
        selected = profile.required ++ profile.optional

        selected =
          if state.permitted == :all,
            do: selected,
            else: Enum.filter(selected, &(&1 in state.permitted))

        configs = Map.merge(Map.get(lease, :runners, %{}), state.runners)
        lease = Runner.prepare(lease, Map.take(configs, selected), profile.execution_controls)
        preview = prepare_preview(state.preview_options, lease, selected)
        lease = put_in(lease.capabilities[:preview], not is_nil(preview))
        services? = not is_nil(preview) and map_size(state.services) > 0
        lease = put_in(lease.capabilities[:services], services?)
        lease = put_in(lease.capabilities[:ports], services?)
        lease = put_in(lease.capabilities[:commands], map_size(state.commands) > 0)

        background =
          Enum.any?(lease.runners, fn {_, runner} -> Runner.reports_progress?(runner) end)

        lease = put_in(lease.capabilities[:background], background)
        state = %{state | lease: lease, profile: profile, preview: preview}

        with :ok <- check_owner(state),
             {:ok, capabilities} <- Profile.admit(profile, lease.capabilities, state.permitted) do
          state = %{state | phase: :open, capabilities: capabilities}
          {:reply, {:ok, info(state)}, state}
        else
          {:error, _} = error ->
            {_, state} = release(state)
            {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  defp open_placement(%{phase: :open} = state, _profile),
    do: {:reply, {:ok, info(state)}, state}

  defp open_placement(state, _profile), do: {:reply, {:error, :session_closed}, state}

  defp check_profile(%{profile: nil}, :configured), do: Profile.resolve(:files)
  defp check_profile(%{profile: profile}, :configured), do: {:ok, profile}
  defp check_profile(%{profile: nil}, profile), do: {:ok, profile}
  defp check_profile(%{profile: profile}, profile), do: {:ok, profile}
  defp check_profile(_, _), do: {:error, :realm_profile_mismatch}

  defp check_owner(%{owner: :down}), do: {:error, :session_closed}

  defp check_owner(%{owner: {pid, _}}) do
    if Process.alive?(pid), do: :ok, else: {:error, :session_closed}
  end

  defp check_owner(%{owner: nil}), do: :ok

  defp made_successful_check?(state, source_ref) when is_binary(source_ref) do
    Enum.any?(state.runs, fn {_, entry} ->
      match?(
        %{request: %{kind: :check}, reply: {:ok, %{source_ref: ^source_ref, status: :succeeded}}},
        entry
      )
    end)
  end

  defp made_successful_check?(_, _), do: false

  defp coding_path(state, operation, path)
       when operation in [:create_revision, :replace_text] and is_binary(path) do
    case Keyword.get(state.coding, :write_paths) do
      nil ->
        :ok

      %Regex{} = regex ->
        if Regex.match?(regex, path), do: :ok, else: {:error, :permission_denied}
    end
  end

  defp coding_path(_, _, _), do: :ok

  defp admit_execution(state, from, work, mode, fingerprint, pinned?, grants) do
    with :ok <- shared_tree_idle(state),
         {:ok, runner} <- select_runner(state, work, mode),
         :ok <- reserve_run(state, pinned?) do
      request = Execution.adapter_request(state.id, state.max_run_ms, work.request)
      id = request.id

      status = %{
        id: id,
        runtime: request[:runtime],
        status: :running,
        output: "",
        truncated: false
      }

      group = {mode, work.target == :runner}

      stored =
        Map.merge(work, %{
          request: request,
          runner: runner,
          mode: mode,
          group: group,
          fingerprint: fingerprint,
          pinned: pinned?,
          status: status,
          reply: {:ok, status}
        })

      state = put_in(state.runs[id], stored)
      {operation, action} = execution(state, stored, grants)

      case mode do
        :sync ->
          start_operation(state, from, operation, action)

        :background ->
          {:noreply, state} = start_operation(state, nil, operation, action)
          {:reply, {:ok, %{id: id}}, state}
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp reserve_run(state, true) do
    if Enum.count(state.runs, fn {_, entry} -> entry.pinned end) < state.max_requests,
      do: :ok,
      else: {:error, :request_limit}
  end

  defp reserve_run(_, false), do: :ok

  defp select_runner(%{phase: :open}, %{target: {:host, _, _}}, :sync), do: {:ok, nil}

  defp select_runner(_, %{target: {:host, _, _}}, :sync), do: {:error, :session_closed}

  defp select_runner(_, %{target: {:host, _, _}}, :background),
    do: {:error, :background_unavailable}

  defp select_runner(state, work, mode) do
    with {:ok, {module, adapter} = runner} <- admit_run(state, work.request.runtime),
         true <- Runner.provides_controls?(module, adapter, work.controls),
         :ok <- admit_mode(state, runner, mode) do
      {:ok, runner}
    else
      false -> {:error, :unsupported_run_options}
      {:error, _} = error -> error
    end
  end

  defp admit_mode(state, runner, :background) do
    if :background in state.capabilities and Runner.reports_progress?(runner),
      do: :ok,
      else: {:error, :background_unavailable}
  end

  defp admit_mode(_, _, :sync), do: :ok

  defp execution(state, %{target: {:host, command, input}, request: %{id: id}}, _grants) do
    binding = state.lease.binding

    {{:command, id},
     fn ->
       value = Commands.run(command, input, binding)
       status = if match?({:error, _}, value), do: :failed, else: :succeeded
       {:ok, %{id: id, status: status, value: value}}
     end}
  end

  defp execution(_, %{runner: runner, request: request, mode: mode}, grants) do
    session = self()
    id = request.id

    request =
      if mode == :background,
        do: Map.put(request, :on_output, &send(session, {:run_output, id, &1, &2})),
        else: request

    {{:run, id},
     fn ->
       case Runner.execute(runner, request, grants) do
         {:ok, result} -> {:ok, Map.merge(result, %{id: id, runtime: request.runtime})}
         {:error, :unknown} -> {:error, {:unknown, id}}
         {:error, _} = error -> error
       end
     end}
  end

  defp admit_file(%{phase: :open, capabilities: capabilities}, operation) do
    if Files.capability(operation) in capabilities do
      :ok
    else
      {:error, :unsupported_file_operation}
    end
  end

  defp admit_file(_, _), do: {:error, :session_closed}

  defp admit_run(
         %{phase: :open, capabilities: capabilities, lease: lease, workers: workers},
         runtime
       ) do
    cond do
      runtime not in capabilities ->
        {:error, :unsupported_runtime}

      Enum.any?(workers, fn {_, worker} -> match?({:run, _}, worker.operation) end) ->
        {:error, :run_in_progress}

      true ->
        Map.fetch(lease.runners, runtime)
    end
  end

  defp admit_run(_, _), do: {:error, :session_closed}

  defp prepare_preview(opts, lease, selected) do
    if Enum.any?([:preview, :services, :ports], &(&1 in selected)) do
      Preview.prepare(opts[:preview], lease, opts)
    end
  end

  defp admit_preview(%{phase: :open} = state) do
    if :preview in state.capabilities,
      do: free_service_slot(state),
      else: {:error, :preview_unavailable}
  end

  defp admit_preview(_), do: {:error, :session_closed}

  defp free_service_slot(state) do
    busy? =
      Enum.any?(state.workers, fn {_, worker} ->
        match?({:preview, _}, worker.operation) or match?({:service, _, _}, worker.operation)
      end)

    if state.service || busy?, do: {:error, :preview_in_progress}, else: :ok
  end

  defp admit_commands(%{phase: :open, capabilities: capabilities}) do
    if :commands in capabilities, do: :ok, else: {:error, :commands_unavailable}
  end

  defp admit_commands(_), do: {:error, :session_closed}

  defp start_operation(state, from, operation, run) do
    session = self()
    ref = make_ref()

    {pid, monitor} =
      :erlang.spawn_opt(
        fn ->
          send(session, {:operation_result, ref, run.()})
        end,
        [:link, :monitor]
      )

    worker = %{from: from, monitor: monitor, pid: pid, operation: operation}
    {:noreply, put_in(state.workers[ref], worker)}
  end

  @impl true
  def handle_info({:operation_result, ref, result}, state) do
    {:noreply, state |> finish_operation(ref, result) |> owner_cleanup()}
  end

  def handle_info({:run_output, id, bytes, discarded?}, state) do
    case state.runs[id] do
      %{status: %{status: :running} = status} ->
        {chunk, clipped} = Runner.clip(bytes, Runner.output_limit() - byte_size(status.output))

        progress = %{
          status
          | output: status.output <> chunk,
            truncated: status.truncated or clipped or discarded?
        }

        {:noreply, put_in(state.runs[id].status, progress)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, pid, _}, %{owner: {pid, monitor}} = state) do
    {_, state} = close_session(%{state | owner: :down})
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    {:noreply, state |> worker_down(monitor) |> owner_cleanup()}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{lease: nil}), do: :ok

  def terminate(_reason, state) do
    deadline = System.monotonic_time(:millisecond) + 1_000

    case await_workers(state, deadline) do
      {:ok, settled} -> release(settled)
      :unknown -> :ok
    end

    :ok
  end

  defp await_workers(%{workers: workers, phase: {:uncertain, _}}, _deadline)
       when map_size(workers) == 0, do: :unknown

  defp await_workers(%{workers: workers} = state, _deadline)
       when map_size(workers) == 0, do: {:ok, state}

  defp await_workers(state, deadline) do
    receive do
      {:operation_result, ref, result} ->
        state |> finish_operation(ref, result) |> await_workers(deadline)

      {:DOWN, monitor, :process, _, _} ->
        state |> worker_down(monitor) |> await_workers(deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        Enum.each(state.workers, fn {_, worker} -> Process.exit(worker.pid, :kill) end)
        :unknown
    end
  end

  defp worker_down(state, monitor) do
    case Enum.find(state.workers, fn {_, worker} -> worker.monitor == monitor end) do
      {ref, worker} -> finish_operation(state, ref, {:error, interrupted(worker.operation)})
      nil -> state
    end
  end

  defp finish_operation(state, ref, result) do
    case Map.pop(state.workers, ref) do
      {%{from: from, monitor: monitor, operation: operation}, workers} ->
        Process.demonitor(monitor, [:flush])
        {result, state} = preview_result(state, operation, result)
        {result, state} = record_result(state, operation, result)
        if from, do: GenServer.reply(from, result)

        phase = run_phase(state.phase, operation, result)
        %{state | workers: workers, phase: phase}

      {nil, _} ->
        state
    end
  end

  defp record_result(state, {kind, id}, result) when kind in [:run, :command] do
    entry = Map.fetch!(state.runs, id)
    reply = Request.result(entry.request, result)
    status = Execution.terminal_status(entry, reply, id)
    runs = Map.put(state.runs, id, %{entry | reply: reply, status: status})

    runs =
      if entry.pinned do
        runs
      else
        Map.reject(runs, fn {key, other} ->
          key != id and not other.pinned and other.group == entry.group and
            other.status.status not in [:running, :unknown]
        end)
      end

    {reply, %{state | runs: runs}}
  end

  defp record_result(state, _, reply), do: {reply, state}

  defp preview_result(state, {:preview, id}, {:ok, handle, target}) do
    private = %{id: id, url: state.preview.base <> "/" <> id <> "/"}
    retain_service(state, id, nil, handle, target, private)
  end

  defp preview_result(state, {:service, id, port_name}, {:ok, handle, target}),
    do: retain_service(state, id, port_name, handle, target, nil)

  defp preview_result(state, {:preview, id}, {:error, reason, handle}),
    do: retain_failed_service(state, id, nil, handle, reason)

  defp preview_result(state, {:service, id, port_name}, {:error, reason, handle}),
    do: retain_failed_service(state, id, port_name, handle, reason)

  defp preview_result(state, _, result), do: {result, state}

  defp retain_service(state, id, port_name, handle, target, private) do
    service = %{
      id: id,
      handle: handle,
      target: target,
      port_name: port_name,
      private: private,
      public: nil
    }

    result =
      if state.phase == :open,
        do: {:ok, private || %{id: id, ports: [port_name]}},
        else: {:error, :session_closed}

    {result, %{state | service: service}}
  end

  defp retain_failed_service(state, id, port_name, handle, reason) do
    service = %{
      id: id,
      handle: handle,
      target: nil,
      port_name: port_name,
      private: nil,
      public: nil
    }

    {{:error, reason}, %{state | phase: closing_phase(state.phase), service: service}}
  end

  defp run_phase(_, {:run, id}, {:error, {:unknown, id}}), do: {:uncertain, id}
  defp run_phase(_, {:preview, id}, {:error, {:unknown, id}}), do: {:uncertain, id}
  defp run_phase(_, {:service, id, _}, {:error, {:unknown, id}}), do: {:uncertain, id}
  defp run_phase(phase, _, _), do: phase

  defp owner_cleanup(%{phase: {:uncertain, _}} = state), do: state

  defp owner_cleanup(%{owner: :down, workers: workers, lease: lease} = state)
       when map_size(workers) == 0 and not is_nil(lease) do
    {_, state} = release(state)
    state
  end

  defp owner_cleanup(state), do: state

  defp close_session(%{lease: nil} = state), do: {:ok, %{state | phase: :closed}}

  defp close_session(%{phase: {:uncertain, id}} = state), do: {{:error, {:unknown, id}}, state}

  defp close_session(%{workers: workers} = state) when map_size(workers) > 0,
    do: {{:error, :close_pending}, %{state | phase: :closing}}

  defp close_session(state), do: release(state)

  defp release(state) do
    {stopped, state} = stop_service(state)

    with :ok <- stopped, :ok <- state.provider.close(state.lease, state.options) do
      {:ok, %{state | phase: :closed, lease: nil, runs: %{}}}
    else
      {:error, _} = error -> {error, %{state | phase: :closing}}
    end
  end

  defp stop_service(%{service: nil} = state), do: {:ok, state}

  defp stop_service(state) do
    %{module: module, state: adapter} = state.preview

    state = update_in(state.service, &%{&1 | target: nil, private: nil, public: nil})

    case module.stop(adapter, state.service.handle) do
      :ok ->
        {:ok, %{state | service: nil}}

      {:error, _} = error ->
        {error, %{state | phase: closing_phase(state.phase)}}
    end
  end

  defp closing_phase({:uncertain, _} = phase), do: phase
  defp closing_phase(_), do: :closing

  defp new_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  defp info(state), do: %{id: state.id, capabilities: state.capabilities}

  # The consumer may have published a write in the destination Realm.
  defp interrupted(:consume), do: :unknown
  defp interrupted(:save), do: :unknown
  defp interrupted({:run, id}), do: {:unknown, id}
  defp interrupted({:preview, id}), do: {:unknown, id}
  defp interrupted({:service, id, _}), do: {:unknown, id}

  defp interrupted(operation) do
    if Files.mutating?(operation), do: :unknown, else: :backend_error
  end

  defp call(session, request, interrupted) do
    GenServer.call(session, request, :infinity)
  catch
    :exit, {:noproc, {GenServer, :call, _}} -> {:error, :session_closed}
    :exit, {_, {GenServer, :call, _}} -> {:error, interrupted}
  end
end
