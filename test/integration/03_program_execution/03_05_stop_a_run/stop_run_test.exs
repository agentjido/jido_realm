defmodule Jido.Realm.Integration.StopRunTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.Runner

  defmodule UncertainRunner do
    @behaviour Runner

    @impl true
    def prepare(:lua, _lease, observer), do: {:ok, observer}

    @impl true
    def execute(observer, request, _grants) do
      send(observer, {:run_started, request.id, self()})

      receive do
        :lose_result -> {:error, :unknown}
      after
        3_000 -> {:error, :unknown}
      end
    end
  end

  defp hold_read(observer) do
    fn
      :read, "input.txt", _, run ->
        send(observer, {:run_waiting, self()})

        receive do
          :go -> run.()
        after
          3_000 -> {:error, :backend_error}
        end

      _, _, _, run ->
        run.()
    end
  end

  realm_case "03.05 enforce the host timeout and discard Lua drafts",
    agent: AgentJobs.Programmer,
    cases: [
      memory: [
        work:
          {BindingFixture,
           kind: :memory,
           runners: %{lua: {Runner.Lua, []}},
           max_run_ms: 150,
           hook: hold_read(self())}
      ]
    ] do
    %{agent: agent, placements: %{work: work}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      work.seed.("report.txt", "prior")
      work.seed.("input.txt", "release")

      work.seed.("main.lua", ~S'''
      assert(realm.write("report.txt", "pending"))
      assert(realm.read("input.txt"))
      ''')

      execution =
        Task.async(fn ->
          AgentJobs.run_result(agent, :lua, "main.lua", %{timeout_ms: 10_000})
        end)

      assert_receive {:run_waiting, worker}, 1_000
      monitor = Process.monitor(worker)
      assert %{status: :timed_out, exit_code: nil, published: []} = Task.await(execution, 2_000)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}

      send(worker, :go)
      assert work.observe.("report.txt") == {:ok, "prior"}
      AgentJobs.succeeded(agent, :close, %{realm: :work})
  end

  realm_case "03.05 keep a session closed to work when the run outcome is unknown",
    agent: AgentJobs.Programmer,
    evidence: :controlled_provider,
    cases: [
      memory: [work: {BindingFixture, kind: :memory, runners: %{lua: {UncertainRunner, self()}}}]
    ] do
    %{agent: agent, instance: instance, bindings: bindings, placements: %{work: work}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      controller = Scenarios.start_agent(instance, AgentJobs.Programmer, bindings)
      work.seed.("main.lua", "return true")
      execution = Task.async(fn -> AgentJobs.run_program(agent, :lua, "main.lua") end)

      assert_receive {:run_started, id, worker}, 1_000

      assert {:ok, %{status: :failed, error: %{details: %{reason: :run_in_progress}}}} =
               AgentJobs.run_program(controller, :lua, "main.lua")

      AgentJobs.rejected(controller, :close, :close_pending, %{realm: :work})
      send(worker, :lose_result)

      assert {:ok, %{status: :failed, error: %{details: %{reason: {:unknown, ^id}}}}} =
               Task.await(execution)

      AgentJobs.rejected(controller, :close, {:unknown, id}, %{realm: :work})
      refute_received {:placement_released, :work, _}
      refute_received {:run_started, _, _}

      Files.assert_rejected(controller, :create, "unsafe.txt", :session_closed, %{
        realm: :work,
        content: "blocked"
      })

      assert work.observe.("unsafe.txt") == {:error, :not_found}
  end

  realm_case "03.05 bound Lua diagnostics without losing the program result",
    agent: AgentJobs.Programmer,
    cases: [lua: [work: {BindingFixture, kind: :memory, runners: %{lua: {Runner.Lua, []}}}]] do
    %{agent: agent, placements: %{work: work}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      work.seed.("main.lua", ~S|print(string.rep("x", 20000))|)

      assert %{status: :succeeded, truncated: true, output: output} =
               AgentJobs.run_result(agent, :lua, "main.lua")

      assert byte_size(output) == Runner.output_limit()
  end

  @tag :docker
  test "03.05 remove the Bash container after timeout and output overflow", context do
    image = System.get_env("JIDO_REALM_BASH_IMAGE", "bash:5.2")
    docker_context = System.get_env("JIDO_REALM_DOCKER_CONTEXT")
    runner = {Runner.Docker, image: image, context: docker_context}
    fixtures = [work: {BindingFixture, kind: :local, runners: %{bash: runner}}]

    %{agent: agent, placements: %{work: work}} =
      Scenarios.prepare(context, AgentJobs.Programmer, fixtures, :bash)

    assert :bash in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
    work.seed.("timeout.sh", "echo started; sleep 30 & wait")
    work.seed.("output.sh", "printf '%020000d' 0; sleep 30")

    assert %{id: timed_out, status: :timed_out, output: "started\n"} =
             AgentJobs.run_result(agent, :bash, "timeout.sh", %{timeout_ms: 1_000})

    assert %{id: overflow, status: :resource_limit, output: output, truncated: true} =
             AgentJobs.run_result(agent, :bash, "output.sh", %{timeout_ms: 5_000})

    assert byte_size(output) == Runner.output_limit()

    prefix = if docker_context, do: ["--context", docker_context], else: []

    for id <- [timed_out, overflow] do
      filter = "name=^/jido-realm-" <> id <> "$"
      assert {"", 0} = System.cmd("docker", prefix ++ ["ps", "-aq", "--filter", filter])
    end

    AgentJobs.succeeded(agent, :close, %{realm: :work})
  end
end
