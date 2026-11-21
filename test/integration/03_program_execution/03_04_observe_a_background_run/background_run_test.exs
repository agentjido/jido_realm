defmodule Jido.Realm.Integration.BackgroundRunTest do
  use ExUnit.Case, parameterize: [%{kind: :local}, %{kind: :memory}]

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.Runner

  test "03.04 resumes agent work while a report runs and observes bounded progress by ID",
       context do
    test = self()

    hook = fn
      :read, "gate", _, run ->
        send(test, {:blocked, self()})

        receive do
          :continue -> run.()
        after
          4_000 -> {:error, :backend_error}
        end

      _, _, _, run ->
        run.()
    end

    script = """
    print('preparing report')
    print(string.rep('x', 20000))
    local value = realm.read('gate')
    assert(realm.write('report.txt', value))
    """

    binding =
      {BindingFixture,
       kind: context.kind,
       hook: hook,
       runners: %{lua: {Runner.Lua, []}},
       files: %{"report.lua" => script, "gate" => "42"}}

    %{agent: agent, observe: %{work: observe}} =
      Scenarios.prepare(context, AgentJobs.Programmer, [work: binding], context.kind)

    assert :background in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
    %{id: id} = AgentJobs.succeeded(agent, :start_background, %{realm: :work, path: "report.lua"})
    assert_receive {:blocked, worker}, 2_000

    assert %{id: ^id, status: :running, truncated: true, output: progress} =
             await(
               fn -> AgentJobs.succeeded(agent, :run_status, %{realm: :work, id: id}) end,
               & &1.truncated
             )

    assert byte_size(progress) == Runner.output_limit()
    assert String.starts_with?(progress, "preparing report\n")
    assert observe.("report.txt") == {:error, :not_found}

    Files.assert_reply(agent, :create, "review-note", %{
      realm: :work,
      content: "working in parallel"
    })

    assert observe.("review-note") == {:ok, "working in parallel"}

    AgentJobs.rejected(agent, :start_background, :run_in_progress, %{
      realm: :work,
      path: "report.lua"
    })

    send(worker, :continue)

    result =
      await(
        fn -> AgentJobs.succeeded(agent, :run_status, %{realm: :work, id: id}) end,
        &(&1.status != :running)
      )

    assert %{
             id: ^id,
             status: :succeeded,
             exit_code: 0,
             truncated: true,
             published: ["report.txt"]
           } = result

    assert byte_size(result.output) == Runner.output_limit()
    assert String.starts_with?(result.output, "preparing report\n")
    assert observe.("report.txt") == {:ok, "42"}
    AgentJobs.succeeded(agent, :close, %{realm: :work})
  end

  defp await(read, ready?, attempts \\ 100)
  defp await(read, _ready?, 0), do: read.()

  defp await(read, ready?, attempts) do
    result = read.()

    if ready?.(result) do
      result
    else
      Process.sleep(10)
      await(read, ready?, attempts - 1)
    end
  end
end
