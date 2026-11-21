defmodule Jido.Realm.Integration.CopyTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios, VFSFixture}

  realm_case "01.03 copy a review file between bindings",
    agent: AgentJobs.Pair,
    cases: [
      local_to_memory: [
        source: {BindingFixture, kind: :local},
        target: {BindingFixture, kind: :memory}
      ],
      memory_to_local: [
        source: {BindingFixture, kind: :memory},
        target: {BindingFixture, kind: :local}
      ],
      local_to_vfs: [source: {BindingFixture, kind: :local}, target: VFSFixture],
      vfs_to_local: [source: VFSFixture, target: {BindingFixture, kind: :local}]
    ] do
    %{
      agent: agent,
      instance: instance,
      bindings: bindings,
      observe: %{source: source, target: target}
    } ->
      for realm <- [:source, :target] do
        assert :files in AgentJobs.succeeded(agent, :open, %{realm: realm}).capabilities
      end

      bytes = "Draft for review café\n"
      Files.assert_reply(agent, :create, "draft", %{realm: :source, content: bytes})
      input = %{path: "draft", to: "review"}
      assert %{path: "review"} = AgentJobs.succeeded(agent, :copy, input)
      assert source.("draft") == {:ok, bytes}
      assert target.("review") == {:ok, bytes}

      Files.assert_reply(agent, :edit, "draft", %{realm: :source, content: "later"})
      AgentJobs.rejected(agent, :copy, :already_exists, input)
      assert target.("review") == {:ok, bytes}

      for {realm, grants} <- [source: [:write], target: [:read]] do
        restricted = Map.update!(bindings, realm, &Keyword.put(&1, :grants, grants))
        caller = Scenarios.start_agent(instance, AgentJobs.Pair, restricted)
        AgentJobs.rejected(caller, :copy, :permission_denied, %{input | to: "denied"})
        assert target.("denied") == {:error, :not_found}
      end

      Files.assert_reply(agent, :create, "other", %{realm: :source, content: "other"})
      second = Scenarios.start_agent(instance, AgentJobs.Pair, bindings)

      outcomes =
        for {caller, path, content} <- [{agent, "draft", "later"}, {second, "other", "other"}] do
          Task.async(fn ->
            {content, AgentJobs.call(caller, :copy, %{path: path, to: "contended"})}
          end)
        end
        |> Task.await_many()

      assert [{winner, _}] = Enum.filter(outcomes, &match?({_, {:ok, %{status: :committed}}}, &1))

      assert [{_, _}] =
               Enum.filter(
                 outcomes,
                 &match?(
                   {_, {:ok, %{status: :failed, error: %{details: %{reason: :already_exists}}}}},
                   &1
                 )
               )

      assert target.("contended") == {:ok, winner}
      assert source.("draft") == {:ok, "later"}
      assert source.("other") == {:ok, "other"}

      for realm <- [:source, :target], do: AgentJobs.succeeded(agent, :close, %{realm: realm})
  end
end
