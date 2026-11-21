defmodule Jido.Realm.Host.TestSupport.ActionBoundary do
  @moduledoc "Test adapter for current APIs. See API_SPEC.md for proposed contracts."

  def schema(fields \\ %{}) do
    Zoi.object(Map.merge(%{request_id: Zoi.string(), resource_id: Zoi.string()}, fields))
  end

  def perform(params, context, kind, operation) do
    access = Map.fetch!(context, :workspace_access)

    result =
      case Map.fetch(access.resources, params.resource_id) do
        {:ok, {^kind, handle}} -> operation.(handle, access.store)
        _ -> {:error, :resource_not_found}
      end

    envelope = %{request_id: params.request_id, resource_id: params.resource_id}

    {suffix, envelope} =
      case result do
        {:ok, data} -> {"succeeded", Map.put(envelope, :result, data)}
        {:error, reason} -> {"failed", Map.put(envelope, :error, error_data(reason))}
      end

    if request = Map.get(context, :signal) do
      type = String.replace_suffix(request.type, "requested", suffix)

      reply =
        Jido.Signal.new!(type, Map.put(envelope, :causation_id, request.id),
          source: "/workspace/test-adapter"
        )

      :ok = Jido.Signal.Dispatch.dispatch(reply, {:pid, target: access.reply_to})
    end

    case result do
      {:ok, _} ->
        {:ok, envelope}

      {:error, reason} ->
        {:error, Jido.Error.execution_error("Workspace request failed", %{domain_error: reason})}
    end
  end

  def put(store, resource_id, kind, value) do
    ref = "#{kind}-#{System.unique_integer([:positive, :monotonic])}"
    Agent.update(store, &Map.put(&1, ref, {resource_id, kind, value}))
    ref
  end

  def fetch(store, resource_id, kind, ref) do
    case Agent.get(store, &Map.get(&1, ref)) do
      {^resource_id, ^kind, value} -> {:ok, value}
      _ -> {:error, :resource_not_found}
    end
  end

  def execution_data(record, store, resource_id, expected) do
    record
    |> Map.take([:id, :command, :status, :exit_status, :output, :truncated, :duration_ms])
    |> Map.put(:checked_files, expected != :current and record.files == expected)
    |> Map.put(:file_view_ref, put(store, resource_id, :file_view, record.files))
    |> Map.put(
      :after_files,
      case record.after_files do
        {:error, reason} -> %{error: error_data(reason)}
        view -> %{file_view_ref: put(store, resource_id, :file_view, view)}
      end
    )
  end

  defp error_data({:policy_denied, action}),
    do: %{code: "policy_denied", action: to_string(action)}

  defp error_data(%Jido.Realm.Host.Error{} = error),
    do: %{
      code: to_string(error.code),
      operation: to_string(error.operation),
      resource: error.resource
    }

  defp error_data(%Jido.VFS.Errors.StaleState{}), do: %{code: "stale_revision"}
  defp error_data(:stale_file_view), do: %{code: "stale_file_view"}
  defp error_data(:resource_not_found), do: %{code: "resource_not_found"}
  defp error_data(reason), do: %{code: "operation_failed", cause: inspect(reason)}
end

defmodule Jido.Realm.Host.TestSupport.Actions.Write do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_test_write",
    schema: Boundary.schema(%{path: Zoi.string(), content: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, _store ->
      with :ok <- Jido.Realm.Host.write(ws, params.path, params.content),
           do: {:ok, %{path: params.path}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Mkdir do
  @moduledoc false
  alias Jido.Realm.Host
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_file_test_mkdir",
    schema: Boundary.schema(%{path: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, _store ->
      with :ok <- Host.mkdir(ws, params.path), do: {:ok, %{path: params.path}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Delete do
  @moduledoc false
  alias Jido.Realm.Host
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_file_test_delete",
    schema: Boundary.schema(%{path: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, _store ->
      with :ok <- Host.delete(ws, params.path), do: {:ok, %{path: params.path}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Close do
  @moduledoc false
  alias Jido.Realm.Host
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_file_test_close", schema: Boundary.schema()

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, _store ->
      with :ok <- Host.close(ws), do: {:ok, %{closed: true}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Run do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_test_run",
    schema:
      Boundary.schema(%{
        command: Zoi.string(),
        file_view_ref: Zoi.string() |> Zoi.optional(),
        timeout_ms: Zoi.integer() |> Zoi.default(30_000),
        output_limit: Zoi.integer() |> Zoi.default(1_048_576)
      })

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, store ->
      expected =
        case Map.get(params, :file_view_ref) do
          nil -> {:ok, :current}
          ref -> Boundary.fetch(store, params.resource_id, :file_view, ref)
        end

      with {:ok, view} <- expected do
        case Jido.Realm.Host.run(ws, params.command,
               files: view,
               timeout_ms: params.timeout_ms,
               output_limit: params.output_limit
             ) do
          {:ok, record} ->
            {:ok, Boundary.execution_data(record, store, params.resource_id, view)}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Info do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_info", schema: Boundary.schema()

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, _ ->
      with {:ok, info} <- Jido.Realm.Host.info(ws),
           do: {:ok, Map.take(info, [:id, :policy, :session])}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.List do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_list", schema: Boundary.schema(%{path: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, _ ->
      with {:ok, entries} <- Jido.Realm.Host.list(ws, params.path),
           do: {:ok, %{entries: Enum.map(entries, &Map.from_struct/1)}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.FileView do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_file_view", schema: Boundary.schema()

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, store ->
      with {:ok, view} <- Jido.Realm.Host.file_view(ws),
           do: {:ok, %{file_view_ref: Boundary.put(store, params.resource_id, :file_view, view)}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.StartSession do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_start_session", schema: Boundary.schema()

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, store ->
      with {:ok, session} <- Jido.Realm.Host.start_session(ws),
           do: {:ok, %{session_ref: Boundary.put(store, params.resource_id, :session, session)}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.StopSession do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_stop_session", schema: Boundary.schema()

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, _ ->
      with :ok <- Jido.Realm.Host.stop_session(ws), do: {:ok, %{stopped: true}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Filesystem do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_filesystem", schema: Boundary.schema()

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, store ->
      with {:ok, fs} <- Jido.Realm.Host.filesystem(ws),
           do: {:ok, %{filesystem_ref: Boundary.put(store, params.resource_id, :filesystem, fs)}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Shell do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_shell", schema: Boundary.schema()

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, store ->
      with {:ok, session} <- Jido.Realm.Host.shell(ws),
           do: {:ok, %{session_ref: Boundary.put(store, params.resource_id, :session, session)}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Read do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_read", schema: Boundary.schema(%{path: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, _store ->
      with {:ok, content} <- Jido.Realm.Host.read(ws, params.path),
           do: {:ok, %{path: params.path, content: content}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Capture do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary
  use Jido.Action, name: "workspace_test_capture", schema: Boundary.schema()

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, store ->
      with {:ok, capture, revision} <- Jido.Realm.Host.capture(ws) do
        {:ok,
         %{
           capture_ref: Boundary.put(store, params.resource_id, :capture, capture),
           revision_ref: Boundary.put(store, params.resource_id, :revision, revision)
         }}
      end
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Replace do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_test_replace",
    schema: Boundary.schema(%{capture_ref: Zoi.string(), revision_ref: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :workspace, fn ws, store ->
      with {:ok, capture} <-
             Boundary.fetch(store, params.resource_id, :capture, params.capture_ref),
           {:ok, revision} <-
             Boundary.fetch(store, params.resource_id, :revision, params.revision_ref),
           {:ok, next} <- Jido.Realm.Host.replace(ws, capture, expected: revision) do
        {:ok, %{revision_ref: Boundary.put(store, params.resource_id, :revision, next)}}
      end
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Exec do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_test_exec",
    schema: Boundary.schema(%{executable: Zoi.string(), args: Zoi.list(Zoi.string())})

  def run(params, context) do
    Boundary.perform(params, context, :sandbox, fn sandbox, _store ->
      with {:ok, execution} <-
             Jido.Realm.Host.Sandbox.exec(sandbox, params.executable, params.args) do
        {:ok, Map.take(execution, [:output, :exit_status, :truncated])}
      end
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Prepare do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_test_prepare",
    schema: Boundary.schema(%{artifact_ref: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :deployment, fn session, store ->
      with {:ok, artifact} <-
             Boundary.fetch(store, params.resource_id, :artifact, params.artifact_ref),
           {:ok, plan} <- Jido.Realm.Host.Deploy.prepare(session, artifact) do
        {:ok, %{plan_ref: Boundary.put(store, params.resource_id, :plan, plan)}}
      end
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Apply do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_test_apply",
    schema: Boundary.schema(%{plan_ref: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :deployment, fn session, store ->
      with {:ok, plan} <- Boundary.fetch(store, params.resource_id, :plan, params.plan_ref),
           {:ok, id} <- Jido.Realm.Host.Deploy.apply(session, plan),
           do: {:ok, %{operation_id: id}}
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.Actions.Await do
  @moduledoc false
  alias Jido.Realm.Host.TestSupport.ActionBoundary, as: Boundary

  use Jido.Action,
    name: "workspace_test_await",
    schema: Boundary.schema(%{operation_id: Zoi.string()})

  def run(params, context) do
    Boundary.perform(params, context, :deployment, fn session, _store ->
      with {:ok, record} <- Jido.Realm.Host.Deploy.await(session, params.operation_id) do
        {:ok,
         %{
           operation_id: record.id,
           status: to_string(record.status),
           source_id: record.snapshot_id,
           digest: record.digest,
           step_count: length(record.steps),
           state_policy: to_string(record.evidence.state_policy)
         }}
      end
    end)
  end
end

defmodule Jido.Realm.Host.TestSupport.BoundaryAgent do
  @moduledoc "A fixed Jido Agent for API integration evidence. It does not use a model."
  alias Jido.Realm.Host.TestSupport.Actions

  use Jido.Agent, name: "workspace_boundary_test"

  state do
    schema(Jido.Joi.object(%{}))
  end

  routes do
    route "realm.host.v1.write.requested", Actions.Write do
      state(:unchanged)
    end

    route "realm.host.v1.read.requested", Actions.Read do
      state(:unchanged)
    end

    route "realm.host.v1.mkdir.requested", Actions.Mkdir do
      state(:unchanged)
    end

    route "realm.host.v1.delete.requested", Actions.Delete do
      state(:unchanged)
    end

    route "realm.host.v1.close.requested", Actions.Close do
      state(:unchanged)
    end

    route "realm.host.v1.run.requested", Actions.Run do
      state(:unchanged)
    end

    route "realm.host.v1.info.requested", Actions.Info do
      state(:unchanged)
    end

    route "realm.host.v1.list.requested", Actions.List do
      state(:unchanged)
    end

    route "realm.host.v1.file_view.requested", Actions.FileView do
      state(:unchanged)
    end

    route "realm.host.v1.start_session.requested", Actions.StartSession do
      state(:unchanged)
    end

    route "realm.host.v1.stop_session.requested", Actions.StopSession do
      state(:unchanged)
    end

    route "realm.host.v1.filesystem.requested", Actions.Filesystem do
      state(:unchanged)
    end

    route "realm.host.v1.shell.requested", Actions.Shell do
      state(:unchanged)
    end

    route "realm.host.v1.capture.requested", Actions.Capture do
      state(:unchanged)
    end

    route "realm.host.v1.replace.requested", Actions.Replace do
      state(:unchanged)
    end

    route "realm.host.v1.sandbox.exec.requested", Actions.Exec do
      state(:unchanged)
    end

    route "realm.host.v1.deploy.prepare.requested", Actions.Prepare do
      state(:unchanged)
    end

    route "realm.host.v1.deploy.apply.requested", Actions.Apply do
      state(:unchanged)
    end

    route "realm.host.v1.deploy.await.requested", Actions.Await do
      state(:unchanged)
    end
  end
end
