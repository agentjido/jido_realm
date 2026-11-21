defmodule Jido.Realm.Integration.CloseDuringWorkTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}

  defp hold(owner) do
    fn :create, path, _, run ->
      send(owner, {:admitted, path, self()})

      receive do
        :finish_write -> run.()
      after
        3_000 -> {:error, :backend_error}
      end
    end
  end

  defp lease_owner do
    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> send(pid, :stop) end)
    pid
  end

  defp drop_write_reply(observer) do
    fn :create, path, _, run ->
      :ok = run.()
      send(observer, {:write_applied, path, self()})

      receive do
        :drop_reply -> exit(:lost_reply)
      after
        3_000 -> exit(:test_barrier_timeout)
      end
    end
  end

  realm_case "00.04 close drains admitted work and reconciles a lost release reply",
    agent: AgentJobs.Work,
    cases: [
      borrowed_local: [
        work: {BindingFixture, kind: :local, lose_release: true, hook: hold(self())}
      ],
      owned_memory: [
        work:
          {BindingFixture, kind: :memory, mode: :owned, lose_release: true, hook: hold(self())}
      ]
    ] do
    %{agent: agent, instance: instance, bindings: bindings, placements: %{work: work}} ->
      controller = Scenarios.start_agent(instance, AgentJobs.Work, bindings)
      AgentJobs.succeeded(agent, :open, %{realm: :work})

      write =
        Task.async(fn ->
          Files.assert_reply(agent, :create, "first", %{realm: :work, content: "admitted"})
        end)

      assert_receive {:admitted, "first", worker}, 1_000
      AgentJobs.rejected(controller, :close, :close_pending, %{realm: :work})

      Files.assert_rejected(controller, :create, "late", :session_closed, %{
        realm: :work,
        content: "denied"
      })

      refute_received {:admitted, "late", _}
      refute_received {:placement_released, :work, _}

      send(worker, :finish_write)
      Task.await(write)
      assert work.observe.("first") == {:ok, "admitted"}
      AgentJobs.rejected(controller, :close, :unknown, %{realm: :work})
      assert_receive {:placement_released, :work, ownership}
      assert ownership == work.ownership
      AgentJobs.succeeded(controller, :close, %{realm: :work})
      refute_received {:placement_released, :work, _}

      expected = if ownership == :borrowed, do: {:ok, "admitted"}, else: {:error, :not_found}
      assert work.observe.("first") == expected
      assert work.observe.("late") == {:error, :not_found}
  end

  realm_case "00.04 close a lease after its owner dies and a write reply is lost",
    agent: AgentJobs.Work,
    cases: [
      owned_local: [
        work:
          {BindingFixture,
           kind: :local, mode: :owned, owner: lease_owner(), hook: drop_write_reply(self())}
      ],
      borrowed_memory: [
        work:
          {BindingFixture, kind: :memory, owner: lease_owner(), hook: drop_write_reply(self())}
      ]
    ] do
    %{agent: agent, instance: instance, bindings: bindings, placements: %{work: work}} ->
      controller = Scenarios.start_agent(instance, AgentJobs.Work, bindings)
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      monitor = Process.monitor(work.owner)

      write =
        Task.async(fn ->
          Files.assert_rejected(agent, :create, "note", :unknown, %{
            realm: :work,
            content: "saved"
          })
        end)

      assert_receive {:write_applied, "note", worker}, 1_000
      assert work.observe.("note") == {:ok, "saved"}
      send(work.owner, :stop)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}

      Files.assert_rejected(controller, :create, "late", :session_closed, %{
        realm: :work,
        content: "denied"
      })

      refute_received {:placement_released, :work, _}

      send(worker, :drop_reply)
      Task.await(write)
      assert_receive {:placement_released, :work, ownership}, 1_000
      assert ownership == work.ownership
      expected = if ownership == :owned, do: {:error, :not_found}, else: {:ok, "saved"}
      assert work.observe.("note") == expected
      assert work.observe.("late") == {:error, :not_found}
      refute_received {:write_applied, _, _}
      AgentJobs.succeeded(controller, :close, %{realm: :work})
      refute_received {:placement_released, :work, _}
  end

  realm_case "00.04 release a lease on session shutdown and reject the old handle",
    agent: AgentJobs.Work,
    cases: [
      owned_local: [work: {BindingFixture, kind: :local, mode: :owned}],
      borrowed_memory: [work: {BindingFixture, kind: :memory}]
    ] do
    %{agent: agent, bindings: bindings, placements: %{work: work}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      Files.assert_reply(agent, :create, "note", %{realm: :work, content: "saved"})
      session = Keyword.fetch!(bindings.work, :session)
      monitor = Process.monitor(session)

      :ok = GenServer.stop(session)

      assert_receive {:DOWN, ^monitor, :process, ^session, :normal}
      assert_receive {:placement_released, :work, ownership}
      assert ownership == work.ownership

      Files.assert_rejected(agent, :edit, "note", :session_closed, %{
        realm: :work,
        content: "late"
      })

      expected = if ownership == :owned, do: {:error, :not_found}, else: {:ok, "saved"}
      assert work.observe.("note") == expected
  end
end
