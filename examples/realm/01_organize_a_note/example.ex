defmodule Jido.Realm.Examples.OrganizeNote do
  @moduledoc "An agent that moves a draft into its final file in one Realm."

  defmodule Action do
    alias Jido.Agent.Directive
    alias Jido.Joi
    alias Jido.Realm

    use Jido.Action,
      name: "organize_note",
      schema:
        Joi.object(%{
          realm: Joi.atom(),
          from: Joi.string(),
          to: Joi.string(),
          text: Joi.string()
        })

    @impl true
    def run(%{realm: realm, from: from, to: to, text: text}, context) do
      with {:ok, _} <- Realm.file(context, realm, :create, from, text),
           {:ok, %{content: draft}} <- Realm.file(context, realm, :read, from),
           {:ok, _} <- Realm.file(context, realm, :create, to, draft),
           {:ok, _} <- Realm.file(context, realm, :delete, from),
           {:ok, reply} <-
             Jido.Agent.build_signal(context, "realm.test.note.organized", %{path: to}) do
        {:ok, context.agent_state, [Directive.reply(reply)]}
      end
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "realm_note_agent",
      plugins: [Jido.Realm.Plugin]

    realms do
      realm(:work, profile: :files)
    end

    routes do
      signal_source("/test/realm/note-agent")
      route("realm.test.note.organize", Jido.Realm.Examples.OrganizeNote.Action)
    end
  end
end
