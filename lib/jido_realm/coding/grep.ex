defmodule Jido.Realm.Coding.Grep do
  @moduledoc "Find lines containing text. Set native for guest ripgrep or regex."

  alias Jido.Joi
  alias Jido.Realm.Coding

  use Jido.Action,
    name: "grep",
    description: "Find lines containing text. Set native for guest ripgrep or regex.",
    schema:
      Joi.object(
        %{
          path: Joi.string() |> Joi.optional(),
          query: Joi.string() |> Joi.min(1) |> Joi.max(256),
          regex: Joi.boolean() |> Joi.optional(),
          native: Joi.boolean() |> Joi.optional(),
          limit: Joi.integer() |> Joi.min(1) |> Joi.max(100) |> Joi.optional(),
          realm: Joi.string() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, context) do
    Coding.grep(context, params)
    |> Coding.result(params[:path])
  end
end
