defmodule Jido.Realm.Integration.SearchTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files}

  realm_case "01.06 find readable text only in the approved subtree",
    agent: AgentJobs.Work,
    cases: [
      local: [work: {BindingFixture, kind: :local}],
      memory: [work: {BindingFixture, kind: :memory}]
    ] do
    %{agent: agent, placements: %{work: work}} ->
      assert :search in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
      work.seed.("approved/a.txt", "needle")
      work.seed.("approved/nested/b.txt", "needle")
      work.seed.("approved/raw.bin", <<255>> <> "needle")
      work.seed.("outside/private.txt", "needle")

      Files.assert_reply(
        agent,
        :search,
        "approved",
        %{realm: :work, query: "needle", limit: 10},
        %{matches: ["approved/a.txt", "approved/nested/b.txt"], limit: 10, truncated: false}
      )

      Files.assert_reply(
        agent,
        :search,
        "approved",
        %{realm: :work, query: "needle", limit: 1},
        %{matches: ["approved/a.txt"], limit: 1, truncated: true}
      )

      Files.assert_reply(agent, :read, "approved/nested/b.txt", %{realm: :work}, %{
        content: "needle"
      })

      assert work.observe.("outside/private.txt") == {:ok, "needle"}
      AgentJobs.succeeded(agent, :close, %{realm: :work})
  end
end
