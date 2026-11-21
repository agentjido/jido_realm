defmodule Jido.Realm.FileAction do
  @moduledoc false

  alias Jido.Joi
  alias Jido.Realm.Plugin

  use Jido.Action,
    name: "realm_file",
    description: "Works with files under the Realm root.",
    schema:
      Joi.object(
        %{
          path: Joi.string() |> Joi.min(1),
          content: Joi.string() |> Joi.optional(),
          destination: Joi.string() |> Joi.optional(),
          revision: Joi.string() |> Joi.optional(),
          request_id: Joi.string() |> Joi.optional(),
          query: Joi.string() |> Joi.optional(),
          limit: Joi.integer() |> Joi.optional(),
          realm: Joi.union([Joi.atom(), Joi.string()]) |> Joi.optional()
        },
        coerce: true,
        unrecognized_keys: :error
      )

  @impl true
  def run(
        %{path: path} = params,
        %{plugin_inputs: %{Plugin => %{runtime: %{operation: operation}}}} = context
      ) do
    context = %{context | agent_signal_source: context.agent_signal_source || "/jido/realm"}

    with {:ok, result} <-
           Jido.Realm.file(
             context,
             params[:realm],
             operation,
             path,
             signal_input(operation, params)
           ),
         {:ok, reply} <- Jido.Agent.build_signal(context, "realm.file.result", result) do
      {:ok, result, [Jido.Agent.Directive.reply(reply)]}
    else
      {:error, reason}
      when is_atom(reason) or (is_tuple(reason) and elem(reason, 0) == :unknown) ->
        {:error,
         Jido.Error.execution_error("Realm file operation failed",
           details: %{code: :realm_file_error, operation: operation, path: path, reason: reason}
         )}

      {:error, _} = error ->
        error
    end
  end

  def run(_params, _context), do: {:error, :live_realm_required}

  defp signal_input(:rename, params), do: params[:destination]
  defp signal_input(:search, params), do: {params[:query], params[:limit] || 100}
  defp signal_input(:edit_revision, params), do: {params[:revision], params[:content]}
  defp signal_input(:delete_revision, params), do: params[:revision]
  defp signal_input(:reconcile, params), do: params[:request_id]
  defp signal_input(_, params), do: params[:content]
end
