defmodule Jido.Realm.Integration.AdmissionTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}

  defp restricted(kind, mode, report, permitted) do
    {BindingFixture,
     kind: kind, mode: mode, report: %{isolation: report, streams: false}, permitted: permitted}
  end

  realm_case "02.03 expose only verified and granted capabilities",
    agent: AgentJobs.Restricted,
    evidence: :controlled_provider,
    cases: [
      local: [work: restricted(:local, :borrowed, true, [:files, :isolation, :tree, :streams])],
      memory: [work: restricted(:memory, :owned, true, [:files, :isolation, :tree, :streams])]
    ] do
    %{agent: agent} ->
      assert %{capabilities: [:files, :isolation, :tree]} =
               AgentJobs.succeeded(agent, :open, %{realm: :work})

      Files.assert_reply(agent, :create, "note", %{realm: :work, content: "allowed"})

      Files.assert_rejected(agent, :search, ".", :unsupported_file_operation, %{
        realm: :work,
        query: "allowed"
      })

      AgentJobs.succeeded(agent, :close, %{realm: :work})
  end

  realm_case "02.03 refuse readiness and release a lease when a required control fails",
    agent: AgentJobs.Restricted,
    evidence: :controlled_provider,
    cases: [
      unsupported_owned_local: [work: restricted(:local, :owned, false, :all)],
      unknown_borrowed_memory: [work: restricted(:memory, :borrowed, :unknown, :all)],
      ungranted_owned_memory: [work: restricted(:memory, :owned, true, [:files])]
    ] do
    %{agent: agent, placements: %{work: work}} ->
      AgentJobs.rejected(agent, :open, {:required_capability_unavailable, :isolation}, %{
        realm: :work
      })

      assert_receive {:placement_opened, :work, placement}
      assert_receive {:placement_released, :work, ownership}
      assert ownership == work.ownership

      Files.assert_rejected(agent, :create, "note", :session_closed, %{
        realm: :work,
        content: "denied"
      })

      assert work.observe.("note") == {:error, :not_found}

      case placement do
        root when is_binary(root) -> assert File.dir?(root) == (ownership == :borrowed)
        pid when is_pid(pid) -> assert Process.alive?(pid) == (ownership == :borrowed)
      end
  end

  realm_case "02.03 prevent a different Profile from using an open lease",
    agent: AgentJobs.Work,
    cases: [memory: [work: {BindingFixture, kind: :memory}]] do
    %{agent: agent, instance: instance, bindings: bindings, observe: %{work: observe}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      restricted = Scenarios.start_agent(instance, AgentJobs.Restricted, bindings)
      AgentJobs.rejected(restricted, :open, :realm_profile_mismatch, %{realm: :work})

      Files.assert_rejected(restricted, :create, "note", :realm_profile_mismatch, %{
        realm: :work,
        content: "blocked"
      })

      assert observe.("note") == {:error, :not_found}
      AgentJobs.rejected(restricted, :close, :realm_profile_mismatch, %{realm: :work})
      AgentJobs.succeeded(agent, :close, %{realm: :work})
  end
end
