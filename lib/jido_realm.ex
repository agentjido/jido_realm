defmodule Jido.Realm do
  @moduledoc """
  Gives a Jido agent a place to work.

  Add `Jido.Realm.Plugin` to the agent and declare named Realms in `realms`.
  The host binds each name to a file backend or a managed `Jido.Realm.Session`.
  Managed sessions expose explicit open, effective capabilities, and close.
  """

  alias Jido.Realm.{Artifacts, Files, Plugin, Runner, Session}

  @doc "Opens the host-approved placement for a named Realm."
  def open(context, realm), do: lifecycle(context, realm, :open)

  @doc "Closes the session. Retry after admitted work has drained or release is unconfirmed."
  def close(context, realm), do: lifecycle(context, realm, :close)

  @doc """
  Saves a portable snapshot of a quiescent Realm that supports snapshots.

  With `:verified_by`, the saved tree must match the result of that successful
  check. Give the binding the `:read` and `:save` grants.
  """
  def save(context, realm, opts \\ []) do
    with {:ok, pid, profile, _} <- managed(context, realm, [:read, :save]),
         {:ok, opts} <- Jido.Realm.Execution.options(opts, [:verified_by]) do
      Session.save(pid, profile, opts[:verified_by])
    end
  end

  @doc """
  Executes work in a managed Realm.

  Use `{:entrypoint, runtime, path}`, `{:shell, :bash, command}`, or
  `{:command, name, arguments}`. The host selects the runtime and allows
  shell commands and named commands explicitly.

  Pass `:request_id` to replay a request or recover its result with
  `run_status/3`. Pass `mode: :background` on a runner that reports progress.
  """
  def exec(context, realm, request) when is_tuple(request),
    do: exec(context, realm, request, [])

  def exec(context, realm, {kind, _, _} = request, opts)
      when kind in [:entrypoint, :shell, :command] do
    with {:ok, opts} <- exec_options(opts) do
      execute(context, realm, request, opts)
    end
  end

  def exec(_context, _realm, request, _opts) when is_tuple(request),
    do: {:error, :invalid_run_options}

  def exec(context, realm, runtime, entrypoint),
    do: exec(context, realm, runtime, entrypoint, [])

  @doc "Executes a Realm entry point with literal arguments and optional declared outputs."
  def exec(context, realm, runtime, entrypoint, opts),
    do: legacy_entrypoint(context, realm, runtime, entrypoint, opts, [])

  @doc "Alias for `exec/5`."
  def run(context, realm, runtime, entrypoint, opts \\ []),
    do: exec(context, realm, runtime, entrypoint, opts)

  @doc "Starts a run on a runner that reports progress and returns its run ID."
  def start_run(context, realm, runtime, entrypoint, opts \\ []),
    do: legacy_entrypoint(context, realm, runtime, entrypoint, opts, mode: :background)

  @doc "Executes a Bash command, named check, or search for an existing coding action."
  def coding_run(context, realm, kind, params, opts \\ []) do
    with {:ok, opts} <- exec_options(opts) do
      execute(context, realm, {:coding, kind, params}, opts)
    end
  end

  @doc "Returns the recorded run status, progress, or terminal result."
  def run_status(context, realm, id) do
    with {:ok, pid, profile, grants} <- managed(context, realm, [:read]) do
      Session.run_status(pid, profile, id, grants)
    end
  end

  defp legacy_entrypoint(context, realm, runtime, entrypoint, opts, execution) do
    with {:ok, pid, profile, grants} <- managed(context, realm, [:read, :run]),
         {:ok, request} <- Runner.request(runtime, entrypoint, opts) do
      Session.execute(pid, profile, {:prepared, request}, execution, grants)
    end
  end

  defp execute(context, realm, request, opts) do
    required = if match?({:command, _, _}, request), do: [:read], else: [:read, :run]

    with {:ok, pid, profile, grants} <- managed(context, realm, required) do
      Session.execute(pid, profile, request, opts, grants)
    end
  end

  defp exec_options(opts) do
    if Keyword.keyword?(opts), do: {:ok, opts}, else: {:error, :invalid_run_options}
  end

  @doc """
  Starts a host-registered service and returns its ID after readiness.
  A service can require `:verified_by`, the ID of a successful named check.
  """
  def start_service(context, realm, name, opts \\ []) do
    with {:ok, pid, profile, _} <- managed(context, realm, [:read, :run, :service]) do
      Session.service(pid, profile, {:start, name, opts})
    end
  end

  @doc "Revokes the service's endpoints and stops the service."
  def stop_service(context, realm, id) do
    with {:ok, pid, profile, _} <- managed(context, realm, [:service]) do
      Session.service(pid, profile, {:stop, id})
    end
  end

  @doc """
  Opens a gateway endpoint for a configured service port.
  Private access is the default. Public access also requires a bounded
  `:ttl_ms` and the host's publication grant.
  """
  def expose_port(context, realm, service_id, name, opts \\ []) do
    with {:ok, opts} <- exec_options(opts),
         {:ok, opts} <- validate_port_options(opts),
         {:ok, pid, profile, _} <- managed(context, realm, port_grants(opts[:access])) do
      Session.service(pid, profile, {:expose, service_id, name, opts})
    end
  end

  @doc "Closes a gateway endpoint. The service stays running."
  def close_port(context, realm, endpoint_id) do
    with {:ok, pid, profile, grants} <- managed(context, realm, [:expose]) do
      Session.service(pid, profile, {:close_port, endpoint_id, grants})
    end
  end

  defp validate_port_options(opts) do
    with {:ok, opts} <- Keyword.validate(opts, access: :private, ttl_ms: nil),
         true <- opts[:access] in [:private, :public],
         true <- opts[:access] == :public or is_nil(opts[:ttl_ms]) do
      {:ok, opts}
    else
      _ -> {:error, :invalid_port_options}
    end
  end

  defp port_grants(:public), do: [:expose, :publish_preview]
  defp port_grants(:private), do: [:expose]

  @doc "Starts a service and returns its private URL after the adapter confirms readiness."
  def start_preview(context, realm, runtime, entrypoint, opts \\ [])

  def start_preview(context, realm, runtime, service, [{:source_ref, source_ref}])
      when runtime in [:bash, "bash"],
      do: start_checked_preview(context, realm, service, source_ref)

  def start_preview(context, realm, runtime, entrypoint, opts) do
    with {:ok, binding} <- binding(context, realm),
         :ok <- authorize(binding, :preview),
         :ok <- authorize(binding, :run),
         :ok <- authorize(binding, :read),
         {:ok, request} <- Runner.preview_request(runtime, entrypoint, opts),
         false <- Map.has_key?(request, :outputs) do
      case binding.target do
        {:session, pid, profile} -> Session.start_preview(pid, profile, request)
        _ -> {:error, :managed_session_required}
      end
    else
      true -> {:error, :invalid_run_options}
      {:error, _} = error -> error
    end
  end

  @doc """
  Starts a private service using the source and toolchain from a successful check.
  The host registers the service command in the session's coding configuration.
  """
  def start_checked_preview(context, realm, name, source_ref) do
    with {:ok, binding} <- binding(context, realm),
         :ok <- authorize(binding, :preview),
         :ok <- authorize(binding, :run),
         :ok <- authorize(binding, :read) do
      case binding.target do
        {:session, pid, profile} -> Session.start_checked_preview(pid, profile, name, source_ref)
        _ -> {:error, :managed_session_required}
      end
    end
  end

  @doc "Revokes the private route and stops its service."
  def stop_preview(context, realm, id) do
    with {:ok, binding} <- binding(context, realm),
         :ok <- authorize(binding, :preview) do
      case binding.target do
        {:session, pid, profile} -> Session.stop_preview(pid, profile, id)
        _ -> {:error, :managed_session_required}
      end
    end
  end

  @doc "Publishes an independent anonymous HTTPS route for a limited time."
  def share_preview(context, realm, id, ttl_ms),
    do: preview_access(context, realm, {:share, id, ttl_ms})

  @doc "Revokes the public route and keeps the private service available."
  def unshare_preview(context, realm, id), do: preview_access(context, realm, {:unshare, id})

  @doc "Lists the host-approved Realm commands the agent can invoke."
  def commands(context, realm) do
    with {:ok, binding} <- binding(context, realm), :ok <- authorize(binding, :read) do
      case binding.target do
        {:session, pid, profile} -> Session.commands(pid, profile, binding.grants)
        _ -> {:error, :managed_session_required}
      end
    end
  end

  @doc "Invokes a registered command using its original return shape."
  def invoke(context, realm, name, input) do
    with {:ok, result} <- exec(context, realm, {:command, name, input}) do
      case result do
        %{value: value} -> value
        _ -> {:ok, result}
      end
    end
  end

  @doc "Performs a file operation against a Realm bound to the current Jido action."
  def file(context, realm, operation, path, input \\ nil) do
    with {:ok, binding} <- binding(context, realm),
         :ok <- authorize(binding, operation),
         do: dispatch(binding, operation, path, input)
  end

  @doc "Publishes selected HTML bundle files through the host's configured presenter."
  def publish_artifact(context, realm, entrypoint, paths) do
    with {:ok, binding} <- binding(context, realm),
         :ok <- authorize(binding, :publish),
         :ok <- authorize(binding, :read),
         {:ok, {presenter, handle}} <- artifact_presenter(binding),
         {:ok, files} <- Artifacts.capture(entrypoint, paths, &dispatch(binding, :read, &1, nil)) do
      presenter.publish(handle, entrypoint, files)
    end
  end

  @doc "Copies a file between two authorized Realms. The destination must be new."
  def copy(context, {source, path}, {target, to}) do
    with {:ok, from, into} <- transfer_bindings(context, source, target, :read, :create),
         {:ok, %{content: content}} <- dispatch(from, :read, path, nil),
         do: dispatch(into, :create, to, content)
  end

  @doc "Copies a file and removes its source only if the captured revision still matches."
  def move(context, {source, path}, {target, to}) do
    with {:ok, from, into} <- transfer_bindings(context, source, target, :read_revision, :create),
         :ok <- authorize(from, :delete_revision),
         :ok <- authorize(into, :read),
         {:ok, %{content: content, revision: revision}} <-
           dispatch(from, :read_revision, path, nil),
         {:ok, _} <- dispatch(into, :create, to, content),
         {:ok, %{content: ^content}} <- dispatch(into, :read, to, nil) do
      case dispatch(from, :delete_revision, path, revision) do
        {:ok, _} -> {:ok, %{path: to}}
        {:error, reason} -> {:error, {:incomplete_move, reason}}
      end
    else
      {:ok, %{content: _}} -> {:error, :transfer_verification_failed}
      {:error, _} = error -> error
    end
  end

  @doc "Stages a binary copy before publication. Use `replace: true` to replace a destination."
  def copy_stream(context, {source, path}, {target, to}, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 65_536)
    replace = Keyword.get(opts, :replace, false)

    with {:ok, from, into} <- transfer_bindings(context, source, target, :consume, :write_stream),
         :ok <- Files.validate_stream_options(chunk_size, replace) do
      dispatch(
        from,
        :consume,
        path,
        {chunk_size,
         fn chunks ->
           dispatch(into, :write_stream, to, {chunks, replace})
         end}
      )
    end
  end

  defp lifecycle(context, realm, operation) do
    with {:ok, binding} <- binding(context, realm),
         :ok <- authorize(binding, operation) do
      case binding.target do
        {:session, pid, profile} -> apply(Session, operation, [pid, profile])
        _ -> {:error, :managed_session_required}
      end
    end
  end

  defp artifact_presenter(%{presenter: presenter}), do: {:ok, presenter}
  defp artifact_presenter(_), do: {:error, :artifact_presenter_unavailable}

  defp preview_access(context, realm, operation) do
    with {:ok, binding} <- binding(context, realm),
         :ok <- authorize(binding, :preview),
         :ok <- authorize(binding, :publish_preview) do
      case binding.target do
        {:session, pid, profile} -> Session.preview_access(pid, profile, operation)
        _ -> {:error, :managed_session_required}
      end
    end
  end

  defp transfer_bindings(context, source, target, read, write) do
    with {:ok, from} <- binding(context, source),
         {:ok, into} <- binding(context, target),
         :ok <- authorize(from, read),
         :ok <- authorize(into, write),
         do: {:ok, from, into}
  end

  defp managed(context, realm, required) do
    with {:ok, binding} <- binding(context, realm),
         :ok <- Enum.reduce_while(required, :ok, &authorize_required(&1, &2, binding)) do
      case binding.target do
        {:session, pid, profile} -> {:ok, pid, profile, binding.grants}
        _ -> {:error, :managed_session_required}
      end
    end
  end

  defp authorize_required(grant, :ok, binding) do
    case authorize(binding, grant) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp binding(%{plugin_inputs: %{Plugin => %{runtime: runtime}}}, realm) when is_map(runtime),
    do: Plugin.binding(runtime, realm)

  defp binding(_, _), do: {:error, :live_realm_required}

  defp authorize(%{grants: :all}, _operation), do: :ok

  defp authorize(%{grants: grants}, operation) do
    grant = Files.grant(operation)
    if grant in grants, do: :ok, else: {:error, :permission_denied}
  end

  defp dispatch(%{target: {:session, pid, profile}}, operation, path, input),
    do: Session.file(pid, profile, operation, path, input)

  defp dispatch(%{target: binding}, operation, path, input),
    do: Files.execute(binding, operation, path, input)
end
