defmodule Jido.Realm.Coding.Glob do
  @moduledoc "List Realm files matching a relative glob."

  alias Jido.Joi
  alias Jido.Realm.Coding

  use Jido.Action,
    name: "glob",
    description: "List Realm files matching a relative glob.",
    schema:
      Joi.object(
        %{
          path: Joi.string() |> Joi.optional(),
          pattern: Joi.string(),
          limit: Joi.integer() |> Joi.min(1) |> Joi.max(100) |> Joi.optional(),
          realm: Joi.string() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, context) do
    Coding.glob(context, params)
    |> Coding.result(params[:path])
  end
end
