defmodule Jido.Realm.Integration.RetainedWorkTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.{Local, Memory, Placement, Session}

  realm_case "07.01 a second read-only agent reopens a retained tree under a fresh session",
    agent: AgentJobs.Work,
    cases: [
      local: [work: {BindingFixture, kind: :local}],
      memory: [work: {BindingFixture, kind: :memory}]
    ] do
    %{agent: writer, instance: instance, variant: kind, placements: %{work: work}} ->
      %{id: first} = AgentJobs.succeeded(writer, :open, %{realm: :work})
      assert_receive {:placement_opened, :work, placement}

      contents = %{
        "source.txt" => "verified source",
        "setup.txt" => "use approved runtime",
        "report.html" => "<h1>Ready</h1>"
      }

      for {path, bytes} <- contents do
        Files.assert_reply(writer, :create, path, %{realm: :work, content: bytes})
      end

      AgentJobs.succeeded(writer, :close, %{realm: :work})
      assert_receive {:placement_released, :work, :borrowed}
      backend = if kind == :local, do: Local, else: Memory

      session =
        start_supervised!({Session, provider: {Placement, {:borrow, {backend, placement}}}})

      reviewer =
        Scenarios.start_agent(instance, AgentJobs.Work, %{
          work: [session: session, grants: [:open, :read, :close]]
        })

      %{id: second} = AgentJobs.succeeded(reviewer, :open, %{realm: :work})
      refute first == second

      for {path, bytes} <- contents do
        Files.assert_reply(reviewer, :read, path, %{realm: :work}, %{content: bytes})
        assert work.observe.(path) == {:ok, bytes}
      end

      Files.assert_rejected(writer, :edit, "source.txt", :session_closed, %{
        realm: :work,
        content: "stale"
      })

      Files.assert_rejected(reviewer, :edit, "source.txt", :permission_denied, %{
        realm: :work,
        content: "denied"
      })

      AgentJobs.succeeded(reviewer, :close, %{realm: :work})
      assert work.observe.("source.txt") == {:ok, "verified source"}
  end
end
