defmodule Jido.Realm.Integration.OrganizeNoteTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios, VFSFixture}

  realm_case "00.01 organize a UTF-8 note [file contract]",
    agent: AgentJobs.Work,
    cases: [
      local: [work: {BindingFixture, kind: :local}],
      memory: [work: {BindingFixture, kind: :memory}],
      vfs_memory: [work: VFSFixture]
    ] do
    %{agent: agent, instance: instance, bindings: bindings, observe: %{work: read}} ->
      bytes = "Note café\n"
      data = %{realm: :work, path: "draft.txt", to: "note.txt", text: bytes}
      assert :files in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
      assert %{path: "note.txt"} = AgentJobs.succeeded(agent, :organize, data)
      assert read.("note.txt") == {:ok, bytes}
      assert read.("draft.txt") == {:error, :not_found}

      Files.assert_rejected(agent, :create, "note.txt", :already_exists, %{
        realm: :work,
        content: "different"
      })

      Files.assert_rejected(agent, :read, "draft.txt", :not_found, %{realm: :work})

      Files.assert_rejected(agent, :edit, "draft.txt", :not_found, %{
        realm: :work,
        content: "different"
      })

      Files.assert_rejected(agent, :delete, "draft.txt", :not_found, %{realm: :work})

      reader =
        Scenarios.start_agent(instance, AgentJobs.Work, %{
          work: Keyword.put(bindings.work, :grants, [:read])
        })

      Files.assert_reply(reader, :read, "note.txt", %{realm: :work}, %{content: bytes})

      for operation <- [:create, :edit, :delete] do
        Files.assert_rejected(reader, operation, "note.txt", :permission_denied, %{
          realm: :work,
          content: "different"
        })
      end

      assert read.("note.txt") == {:ok, bytes}
      Files.assert_reply(agent, :edit, "note.txt", %{realm: :work, content: "corrected"})
      assert read.("note.txt") == {:ok, "corrected"}
      AgentJobs.succeeded(agent, :close, %{realm: :work})
      Files.assert_rejected(reader, :read, "note.txt", :session_closed, %{realm: :work})
      assert read.("note.txt") == {:ok, "corrected"}
  end
end
