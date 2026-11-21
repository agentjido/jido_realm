defmodule Jido.Realm.Coding.Bash do
  @moduledoc "Run a Bash command in the guest with read-only source."

  alias Jido.Joi
  alias Jido.Realm
  alias Jido.Realm.Coding

  use Jido.Action,
    name: "bash",
    description: "Run a Bash command in the guest with read-only source.",
    schema:
      Joi.object(
        %{
          command: Joi.string(),
          cwd: Joi.string() |> Joi.optional(),
          timeout_ms: Joi.integer() |> Joi.min(1) |> Joi.max(30_000) |> Joi.optional(),
          realm: Joi.string() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, context) do
    Realm.coding_run(context, params[:realm], :bash, params)
    |> Coding.result(nil)
  end
end
