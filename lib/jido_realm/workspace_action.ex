defmodule Jido.Realm.WorkspaceAction do
  @moduledoc false

  alias Jido.Joi
  alias Jido.Realm
  alias Jido.Realm.Plugin

  use Jido.Action,
    name: "realm_workspace",
    description: "Opens or closes a Realm, or saves an artifact for review.",
    schema:
      Joi.object(
        %{
          realm: Joi.union([Joi.atom(), Joi.string()]),
          entrypoint: Joi.string() |> Joi.optional(),
          paths: Joi.list(Joi.string()) |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, %{plugin_inputs: %{Plugin => %{runtime: %{operation: operation}}}} = context) do
    context = %{context | agent_signal_source: context.agent_signal_source || "/jido/realm"}

    with {:ok, type, result} <- perform(operation, params, context),
         {:ok, reply} <- Jido.Agent.build_signal(context, type, result) do
      {:ok, result, [Jido.Agent.Directive.reply(reply)]}
    else
      {:error, reason} ->
        {:error,
         Jido.Error.execution_error("Realm workspace operation failed",
           details: %{code: :realm_workspace_error, operation: operation, reason: reason}
         )}
    end
  end

  def run(_, _), do: {:error, :live_realm_required}

  defp perform(:open, %{realm: realm} = params, context) when map_size(params) == 1 do
    with {:ok, result} <- Realm.open(context, realm),
         do: {:ok, "realm.opened", Map.put(result, :realm, realm)}
  end

  defp perform(:close, %{realm: realm} = params, context) when map_size(params) == 1 do
    with :ok <- Realm.close(context, realm), do: {:ok, "realm.closed", %{realm: realm}}
  end

  defp perform(:publish, %{realm: realm, entrypoint: entrypoint, paths: paths}, context) do
    with {:ok, artifact} <- Realm.publish_artifact(context, realm, entrypoint, paths),
         do: {:ok, "realm.artifact.published", artifact}
  end

  defp perform(_, _, _), do: {:error, :invalid_workspace_options}
end
