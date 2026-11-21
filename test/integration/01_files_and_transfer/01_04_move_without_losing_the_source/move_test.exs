defmodule Jido.Realm.Integration.MoveTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}

  defp fault(owner) do
    fn
      :create, "failed", _, _ ->
        {:error, :backend_error}

      :create, "unknown", _, run ->
        :ok = run.()
        {:error, :unknown}

      :create, "changed", _, run ->
        :ok = run.()
        send(owner, {:destination_written, self()})

        receive do
          :source_changed -> :ok
        after
          3_000 -> {:error, :backend_error}
        end

      _, _, _, run ->
        run.()
    end
  end

  realm_case "01.04 move only after verified copy and an unchanged source",
    agent: AgentJobs.Pair,
    cases: [
      local_to_memory: [
        source: {BindingFixture, kind: :local, mode: :static},
        target: {BindingFixture, kind: :memory, mode: :static, hook: fault(self())}
      ],
      memory_to_local: [
        source: {BindingFixture, kind: :memory, mode: :static},
        target: {BindingFixture, kind: :local, mode: :static, hook: fault(self())}
      ]
    ] do
    %{
      agent: agent,
      instance: instance,
      bindings: bindings,
      observe: %{source: source, target: target}
    } ->
      Files.assert_reply(agent, :create, "draft", %{realm: :source, content: "copy me"})
      input = %{path: "draft", to: "failed"}
      AgentJobs.rejected(agent, :move, :backend_error, input)
      assert source.("draft") == {:ok, "copy me"}
      assert target.("failed") == {:error, :not_found}

      AgentJobs.rejected(agent, :move, :unknown, %{input | to: "unknown"})
      assert source.("draft") == {:ok, "copy me"}
      assert target.("unknown") == {:ok, "copy me"}

      writer = Scenarios.start_agent(instance, AgentJobs.Pair, bindings)

      transfer =
        Task.async(fn ->
          AgentJobs.rejected(agent, :move, {:incomplete_move, :conflict}, %{input | to: "changed"})
        end)

      assert_receive {:destination_written, worker}, 1_000
      Files.assert_reply(writer, :edit, "draft", %{realm: :source, content: "newer"})
      send(worker, :source_changed)
      Task.await(transfer)
      assert source.("draft") == {:ok, "newer"}
      assert target.("changed") == {:ok, "copy me"}

      AgentJobs.succeeded(agent, :move, %{input | to: "final"})
      assert source.("draft") == {:error, :not_found}
      assert target.("final") == {:ok, "newer"}
  end
end
