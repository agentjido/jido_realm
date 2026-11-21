defmodule Jido.Realm.Integration.PublicationTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.Runner

  defp pause_publication(observer) do
    fn
      :edit_revision, "report.txt", _, run ->
        send(observer, {:ready_to_publish, self()})

        receive do
          :publish -> run.()
        after
          2_000 -> {:error, :backend_error}
        end

      _, _, _, run ->
        run.()
    end
  end

  defp lose_summary_reply(observer) do
    fn
      :edit_revision, "summary.txt", _, run ->
        :ok = run.()
        send(observer, :summary_written)
        {:error, :unknown}

      _, _, _, run ->
        run.()
    end
  end

  realm_case "03.03 preserve a newer edit made while a Lua report is staged",
    agent: AgentJobs.Programmer,
    cases: [
      memory: [
        work:
          {BindingFixture,
           kind: :memory, runners: %{lua: {Runner.Lua, []}}, hook: pause_publication(self())}
      ]
    ] do
    %{agent: agent, instance: instance, bindings: bindings, placements: %{work: work}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      editor = Scenarios.start_agent(instance, AgentJobs.Programmer, bindings)
      work.seed.("report.txt", "prior")
      work.seed.("main.lua", ~S|assert(realm.write("report.txt", "from program"))|)

      execution = Task.async(fn -> AgentJobs.run_result(agent, :lua, "main.lua") end)
      assert_receive {:ready_to_publish, worker}, 1_000
      assert work.observe.("report.txt") == {:ok, "prior"}

      Files.assert_reply(editor, :edit, "report.txt", %{realm: :work, content: "newer edit"})
      send(worker, :publish)

      assert %{
               status: :publication_failed,
               exit_code: 0,
               published: [],
               publication_error: %{path: "report.txt", reason: :conflict}
             } = Task.await(execution)

      assert work.observe.("report.txt") == {:ok, "newer edit"}
  end

  realm_case "03.03 report which files were confirmed after a lost publication reply",
    agent: AgentJobs.Programmer,
    cases: [
      memory: [
        work:
          {BindingFixture,
           kind: :memory, runners: %{lua: {Runner.Lua, []}}, hook: lose_summary_reply(self())}
      ]
    ] do
    %{agent: agent, placements: %{work: work}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      work.seed.("summary.txt", "prior")

      work.seed.("main.lua", ~S'''
      assert(realm.write("summary.txt", "updated"))
      assert(realm.write("report.txt", realm.read("summary.txt")))
      assert(realm.write("third.txt", "never publish"))
      ''')

      assert %{
               status: :publication_failed,
               published: ["report.txt"],
               publication_error: %{path: "summary.txt", reason: :unknown}
             } = AgentJobs.run_result(agent, :lua, "main.lua")

      assert_received :summary_written
      refute_received :summary_written
      assert work.observe.("report.txt") == {:ok, "updated"}
      assert work.observe.("summary.txt") == {:ok, "updated"}
      assert work.observe.("third.txt") == {:error, :not_found}
  end
end
