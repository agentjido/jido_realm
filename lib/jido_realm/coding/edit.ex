defmodule Jido.Realm.Coding.Edit do
  @moduledoc "Replace one exact text match using the revision from read."

  alias Jido.Joi
  alias Jido.Realm
  alias Jido.Realm.Coding

  use Jido.Action,
    name: "edit",
    description: "Replace one exact text match using the revision from read.",
    schema:
      Joi.object(
        %{
          path: Joi.string(),
          revision: Joi.string(),
          old_text: Joi.string(),
          new_text: Joi.string(),
          realm: Joi.string() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(params, context) do
    Realm.file(
      context,
      params[:realm],
      :replace_text,
      params.path,
      {params.revision, params.old_text, params.new_text}
    )
    |> Coding.result(params[:path])
  end
end
