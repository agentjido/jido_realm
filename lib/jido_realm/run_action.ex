defmodule Jido.Realm.RunAction do
  @moduledoc false

  alias Jido.Joi

  use Jido.Action,
    name: "realm_program_run",
    description: "Runs an entry point from an open Realm with a host-approved runtime.",
    schema:
      Joi.object(
        %{
          realm: Joi.union([Joi.atom(), Joi.string()]),
          runtime: Joi.union([Joi.atom(), Joi.string()]),
          entrypoint: Joi.string(),
          cwd: Joi.string() |> Joi.optional(),
          args: Joi.list(Joi.string()) |> Joi.optional(),
          inputs: Joi.list(Joi.string()) |> Joi.optional(),
          outputs: Joi.list(Joi.string()) |> Joi.optional(),
          timeout_ms: Joi.integer() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, context) do
    context = %{context | agent_signal_source: context.agent_signal_source || "/jido/realm"}
    opts = params |> Map.take([:cwd, :args, :inputs, :outputs, :timeout_ms]) |> Map.to_list()

    with {:ok, result} <-
           Jido.Realm.exec(context, params.realm, params.runtime, params.entrypoint, opts),
         {:ok, reply} <- Jido.Agent.build_signal(context, "realm.program.result", result) do
      {:ok, result, [Jido.Agent.Directive.reply(reply)]}
    else
      {:error, reason} ->
        {:error,
         Jido.Error.execution_error("Realm program could not return a result",
           details: %{code: :realm_run_error, reason: reason}
         )}
    end
  end
end
