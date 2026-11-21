defmodule Jido.Realm.Examples.CopyNote do
  @moduledoc "An agent that copies a note between two named Realms."

  defmodule Action do
    alias Jido.Agent.Directive
    alias Jido.Joi
    alias Jido.Realm

    use Jido.Action,
      name: "copy_note",
      schema: Joi.object(%{from: Joi.string(), to: Joi.string()})

    @impl true
    def run(%{from: from, to: to}, context) do
      with {:ok, %{content: draft}} <- Realm.file(context, :source, :read, from),
           {:ok, _} <- Realm.file(context, :target, :create, to, draft),
           {:ok, reply} <-
             Jido.Agent.build_signal(context, "realm.example.note.copied", %{path: to}) do
        {:ok, context.agent_state, [Directive.reply(reply)]}
      end
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "realm_copy_note_agent", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:source, profile: :files)
      realm(:target, profile: :files)
    end

    routes do
      signal_source("/examples/realm/copy-note")
      route("realm.example.note.copy", Jido.Realm.Examples.CopyNote.Action)
    end
  end
end
