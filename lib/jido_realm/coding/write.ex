defmodule Jido.Realm.Coding.Write do
  @moduledoc "Create a new text file. Existing files are protected."

  alias Jido.Joi
  alias Jido.Realm
  alias Jido.Realm.Coding

  use Jido.Action,
    name: "write",
    description: "Create a new text file. Existing files are protected.",
    schema:
      Joi.object(
        %{
          path: Joi.string(),
          content: Joi.string(),
          realm: Joi.string() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, context) do
    Realm.file(context, params[:realm], :create_revision, params.path, params.content)
    |> Coding.result(params[:path])
  end
end
