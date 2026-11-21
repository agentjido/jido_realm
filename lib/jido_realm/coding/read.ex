defmodule Jido.Realm.Coding.Read do
  @moduledoc "Read one file or up to six paths. Keep the revision for edits."

  alias Jido.Joi
  alias Jido.Realm.Coding

  use Jido.Action,
    name: "read",
    description: "Read one file or up to six paths. Keep the revision for edits.",
    schema:
      Joi.object(
        %{
          path: Joi.string() |> Joi.optional(),
          paths: Joi.list(Joi.string()) |> Joi.max(6) |> Joi.optional(),
          start_line: Joi.integer() |> Joi.min(1) |> Joi.max(100_000) |> Joi.optional(),
          line_count: Joi.integer() |> Joi.min(1) |> Joi.max(200) |> Joi.optional(),
          realm: Joi.string() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, context) do
    Coding.read(context, params)
    |> Coding.result(params[:path])
  end
end
