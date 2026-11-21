defmodule Jido.Realm.Integration.RevisionTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}

  defp read_revision(agent) do
    assert {:ok, %{status: :committed, reply: %{data: %{revision: revision, content: bytes}}}} =
             Files.call(agent, :read_revision, %{realm: :work, path: "note"})

    {revision, bytes}
  end

  realm_case "01.02 two agents contend on the same revision",
    agent: AgentJobs.Work,
    cases: [
      local: [work: {BindingFixture, kind: :local}],
      memory: [work: {BindingFixture, kind: :memory}]
    ] do
    %{agent: first, instance: instance, bindings: bindings, observe: %{work: observe}} ->
      second = Scenarios.start_agent(instance, AgentJobs.Work, bindings)
      assert :revisions in AgentJobs.succeeded(first, :open, %{realm: :work}).capabilities
      Files.assert_reply(first, :create, "note", %{realm: :work, content: "original"})
      assert {baseline, "original"} = read_revision(first)
      assert {^baseline, "original"} = read_revision(second)

      outcomes =
        [{first, "first"}, {second, "second"}]
        |> Enum.map(fn {agent, bytes} ->
          Task.async(fn ->
            params = %{realm: :work, path: "note", revision: baseline, content: bytes}
            {agent, bytes, Files.call(agent, :edit_revision, params)}
          end)
        end)
        |> Task.await_many()

      assert [{_, winner, {:ok, %{status: :committed}}}] =
               Enum.filter(outcomes, fn {_, _, {:ok, result}} -> result.status == :committed end)

      assert [{loser, _, {:ok, %{status: :failed, error: %{details: %{reason: :conflict}}}}}] =
               Enum.filter(outcomes, fn {_, _, {:ok, result}} -> result.status == :failed end)

      assert {new_revision, ^winner} = read_revision(loser)
      assert new_revision != baseline
      assert observe.("note") == {:ok, winner}

      Files.assert_reply(first, :edit, "note", %{realm: :work, content: "original"})
      assert {^baseline, "original"} = read_revision(second)

      Files.assert_reply(second, :edit_revision, "note", %{
        realm: :work,
        revision: baseline,
        content: "same baseline bytes"
      })

      assert observe.("note") == {:ok, "same baseline bytes"}

      AgentJobs.succeeded(first, :close, %{realm: :work})
  end
end
