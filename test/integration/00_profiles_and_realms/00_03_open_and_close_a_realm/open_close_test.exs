defmodule Jido.Realm.Integration.OpenCloseTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files}

  realm_case "00.03 open an approved placement and close its session",
    agent: AgentJobs.Work,
    cases: [
      owned_local: [work: {BindingFixture, kind: :local, mode: :owned}],
      owned_memory: [work: {BindingFixture, kind: :memory, mode: :owned}],
      borrowed_local: [work: {BindingFixture, kind: :local}],
      borrowed_memory: [work: {BindingFixture, kind: :memory}]
    ] do
    %{agent: agent, placements: %{work: work}} ->
      assert work.where.() == nil

      assert %{id: id, capabilities: capabilities} =
               AgentJobs.succeeded(agent, :open, %{realm: :work})

      assert is_binary(id) and :files in capabilities
      assert_receive {:placement_opened, :work, placement}
      assert work.where.() == placement
      assert %{id: ^id} = AgentJobs.succeeded(agent, :open, %{realm: :work})
      refute_received {:placement_opened, :work, _}

      Files.assert_reply(agent, :create, "note", %{realm: :work, content: "saved"})
      assert work.observe.("note") == {:ok, "saved"}
      AgentJobs.succeeded(agent, :close, %{realm: :work})
      assert_receive {:placement_released, :work, ownership}
      assert ownership == work.ownership

      Files.assert_rejected(agent, :edit, "note", :session_closed, %{
        realm: :work,
        content: "late"
      })

      AgentJobs.succeeded(agent, :close, %{realm: :work})
      refute_received {:placement_released, :work, _}

      expected = if ownership == :owned, do: {:error, :not_found}, else: {:ok, "saved"}
      assert work.observe.("note") == expected
  end
end
