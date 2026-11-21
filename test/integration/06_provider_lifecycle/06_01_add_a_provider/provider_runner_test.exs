defmodule Jido.Realm.Integration.ProviderRunnerTest do
  use ExUnit.Case

  alias Jido.Realm.Conformance.{AgentJobs, Files, Scenarios}
  alias Jido.Realm.{Placement, Runner, Session}

  defmodule Provider do
    @behaviour Jido.Realm.Provider

    @impl true
    def open(observer) do
      with {:ok, lease} <- Placement.open(:memory) do
        send(observer, {:provider_opened, lease.placement})
        {:ok, Map.put(lease, :runners, %{lua: {Runner.Lua, []}})}
      end
    end

    @impl true
    def close(lease, observer) do
      with :ok <- Placement.close(lease, []) do
        send(observer, {:provider_closed, lease.placement})
        :ok
      end
    end
  end

  defmodule UnavailableRunner do
    @behaviour Jido.Realm.Runner

    @impl true
    def prepare(:lua, lease, observer) do
      send(observer, {:host_override, lease.placement})
      {:error, :runtime_unavailable}
    end

    @impl true
    def execute(_, _, _), do: raise("Unavailable runner must never execute")
  end

  test "06.01 runs a provider-supplied toolchain against the provider's file tree", context do
    agent = start_job(context, %{})

    assert :lua in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
    assert_receive {:provider_opened, placement}
    script = ~S|assert(realm.write("report.txt", realm.read("seed.txt") .. " compiled"))|
    Files.assert_reply(agent, :create, "build.lua", %{realm: :work, content: script})
    Files.assert_reply(agent, :create, "seed.txt", %{realm: :work, content: "input"})

    assert %{status: :succeeded, published: ["report.txt"]} =
             AgentJobs.run_result(agent, :lua, "build.lua")

    assert Agent.get(placement, &Map.fetch!(&1, "report.txt")) == "input compiled"

    AgentJobs.succeeded(agent, :close, %{realm: :work})
    assert_receive {:provider_closed, ^placement}
    refute Process.alive?(placement)
  end

  test "06.01 an unavailable host override cannot fall through to the provider runner", context do
    agent = start_job(context, %{lua: {UnavailableRunner, self()}})

    refute :lua in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
    assert_receive {:provider_opened, placement}
    assert_receive {:host_override, ^placement}
    script = ~S|assert(realm.write("report.txt", "must not run"))|
    Files.assert_reply(agent, :create, "build.lua", %{realm: :work, content: script})

    assert {:ok, %{status: :failed, error: %{details: %{reason: :unsupported_runtime}}}} =
             AgentJobs.run_program(agent, :lua, "build.lua")

    refute Agent.get(placement, &Map.has_key?(&1, "report.txt"))
    AgentJobs.succeeded(agent, :close, %{realm: :work})
    assert_receive {:provider_closed, ^placement}
  end

  defp start_job(context, runners) do
    session = start_supervised!({Session, provider: {Provider, self()}, runners: runners})
    start_supervised!({Jido, name: context.module})
    Scenarios.start_agent(context.module, AgentJobs.Programmer, %{work: [session: session]})
  end
end
