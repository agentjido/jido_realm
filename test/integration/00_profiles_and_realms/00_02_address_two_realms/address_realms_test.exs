defmodule Jido.Realm.Integration.AddressRealmsTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files}

  realm_case "00.02 keep two named places independent",
    agent: AgentJobs.Pair,
    cases: [
      local_and_memory: [
        source: {BindingFixture, kind: :local},
        target: {BindingFixture, kind: :memory}
      ],
      two_memory_instances: [
        source: {BindingFixture, kind: :memory, mode: :owned},
        target: {BindingFixture, kind: :memory, mode: :owned}
      ]
    ] do
    %{agent: agent, observe: %{source: source, target: target}} ->
      %{id: source_id} = AgentJobs.succeeded(agent, :open, %{realm: :source})
      %{id: target_id} = AgentJobs.succeeded(agent, :open, %{realm: :target})
      assert source_id != target_id

      Files.assert_reply(agent, :create, "note.txt", %{realm: :source, content: "source"})
      Files.assert_reply(agent, :create, "note.txt", %{realm: :target, content: "target"})

      Files.assert_rejected(agent, :create, "blocked.txt", :unknown_realm, %{
        realm: :other,
        content: "denied"
      })

      assert source.("note.txt") == {:ok, "source"}
      assert target.("note.txt") == {:ok, "target"}
      assert source.("blocked.txt") == {:error, :not_found}
      assert target.("blocked.txt") == {:error, :not_found}

      AgentJobs.succeeded(agent, :close, %{realm: :source})
      Files.assert_reply(agent, :read, "note.txt", %{realm: :target}, %{content: "target"})
      AgentJobs.succeeded(agent, :close, %{realm: :target})
  end

  realm_case "00.02 reject an agent job with a missing declared binding",
    agent: AgentJobs.Pair,
    cases: [local_source_only: [source: {BindingFixture, kind: :local}]] do
    %{agent: agent, placements: %{source: source}} ->
      assert {:ok, %{status: :failed, reply: nil, error: :realm_bindings_must_match_declarations}} =
               AgentJobs.call(agent, :open, %{realm: :source})

      refute_received {:placement_opened, :source, _}
      assert source.where.() == nil
  end
end
