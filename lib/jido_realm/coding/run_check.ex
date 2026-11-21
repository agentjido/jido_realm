defmodule Jido.Realm.Coding.RunCheck do
  @moduledoc "Run a host-approved check against a snapshot of the Realm source."

  alias Jido.Joi
  alias Jido.Realm
  alias Jido.Realm.Coding

  use Jido.Action,
    name: "run_check",
    description: "Run a host-approved check against a snapshot of the Realm source.",
    schema:
      Joi.object(
        %{
          name: Joi.string(),
          source_ref: Joi.string() |> Joi.optional(),
          realm: Joi.string() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, context) do
    Realm.coding_run(context, params[:realm], :check, params)
    |> Coding.result(nil)
  end
end
