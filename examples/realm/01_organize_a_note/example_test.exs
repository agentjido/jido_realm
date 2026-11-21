Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Examples.OrganizeNoteTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios, only: [realm_case: 3]

  alias Jido.Realm.Conformance.{LocalFixture, MemoryFixture}
  alias Jido.Realm.Examples.OrganizeNote

  @moduletag :realm_example

  realm_case "move a note into its final file",
    agent: OrganizeNote.Agent,
    cases: [local: [work: LocalFixture], memory: [work: MemoryFixture]] do
    %{agent: agent, observe: %{work: read}} ->
      job =
        Jido.Signal.new!(
          "realm.test.note.organize",
          %{realm: :work, from: "draft.txt", to: "note.txt", text: "Hello from Realm\n"},
          source: "/test/realm"
        )

      assert {:ok,
              %{
                status: :committed,
                reply: %{type: "realm.test.note.organized", data: %{path: "note.txt"}}
              }} = Jido.AgentServer.call(agent, job)

      assert {:ok, "Hello from Realm\n"} = read.("note.txt")
      assert {:error, :not_found} = read.("draft.txt")
  end
end
