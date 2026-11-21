Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Examples.CopyNoteTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios, only: [realm_case: 3]

  alias Jido.Realm.Conformance.{Files, LocalFixture, MemoryFixture}
  alias Jido.Realm.Examples.CopyNote

  @moduletag :realm_example

  realm_case "copy a note for review and protect the existing copy",
    agent: CopyNote.Agent,
    cases: [
      local_to_memory: [source: LocalFixture, target: MemoryFixture],
      memory_to_local: [source: MemoryFixture, target: LocalFixture]
    ] do
    %{agent: agent, observe: %{source: source, target: target}} ->
      draft = "Draft for review café\n"
      revision = "Revised source\n"
      Files.assert_reply(agent, :create, "draft.txt", %{realm: :source, content: draft})

      assert {:ok,
              %{
                status: :committed,
                reply: %{type: "realm.example.note.copied", data: %{path: "review.txt"}}
              }} = copy_note(agent)

      assert {:ok, ^draft} = source.("draft.txt")
      assert {:ok, ^draft} = target.("review.txt")

      Files.assert_reply(agent, :edit, "draft.txt", %{realm: :source, content: revision})
      assert {:ok, %{status: :failed, reply: nil}} = copy_note(agent)
      assert {:ok, ^revision} = source.("draft.txt")
      assert {:ok, ^draft} = target.("review.txt")
  end

  defp copy_note(agent) do
    signal =
      Jido.Signal.new!(
        "realm.example.note.copy",
        %{from: "draft.txt", to: "review.txt"},
        source: "/test/realm"
      )

    Jido.AgentServer.call(agent, signal)
  end
end
