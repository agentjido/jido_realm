defmodule Jido.Realm.Integration.LostOpenTest do
  use ExUnit.Case

  alias Jido.Realm.Conformance.{AgentJobs, Files, Scenarios}
  alias Jido.Realm.{Placement, Session}

  defmodule IdempotentProvider do
    @behaviour Jido.Realm.Provider

    @impl true
    def open(%{record: record, observer: observer}) do
      Agent.get_and_update(record, fn
        nil ->
          {:ok, lease} = Placement.open(:memory)
          send(observer, {:allocated, lease.placement})
          {{:error, :unknown}, lease}

        lease ->
          send(observer, {:recovered, lease.placement})
          {{:ok, lease}, lease}
      end)
    end

    @impl true
    def close(lease, _options), do: Placement.close(lease, [])
  end

  @tag realm_evidence: :controlled_transport
  test "06.02 retries the provider request after a lost allocation reply and recovers one placement",
       context do
    record = start_supervised!({Agent, fn -> nil end})
    opts = %{record: record, observer: self()}
    session = start_supervised!({Session, provider: {IdempotentProvider, opts}})

    start_supervised!({Jido, name: context.module})
    agent = Scenarios.start_agent(context.module, AgentJobs.Work, %{work: [session: session]})

    AgentJobs.rejected(agent, :open, :unknown, %{realm: :work})
    assert_receive {:allocated, placement}

    Files.assert_rejected(agent, :create, "premature", :session_closed, %{
      realm: :work,
      content: "absent"
    })

    AgentJobs.succeeded(agent, :open, %{realm: :work})
    assert_receive {:recovered, ^placement}
    refute_received {:allocated, _}
    Files.assert_reply(agent, :create, "ready", %{realm: :work, content: "confirmed"})
    assert Agent.get(placement, & &1) == %{"ready" => "confirmed"}

    AgentJobs.succeeded(agent, :close, %{realm: :work})
    refute Process.alive?(placement)
  end
end
