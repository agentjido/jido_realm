defmodule Jido.Realm.Integration.GitHubBranchTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, RemoteFixture, Scenarios}

  realm_case "01.08 commit work to a scoped GitHub branch and review a pinned version",
    agent: AgentJobs.Pair,
    evidence: :controlled_transport,
    cases: [
      github_branch: [
        source: {BindingFixture, kind: :local, mode: :static},
        target: {RemoteFixture, store: {:github, "test-repo", "work"}, prefix: "notes"}
      ]
    ] do
    %{agent: agent, instance: instance, placements: %{target: remote}} ->
      %{client: client, scope: %{store: {:github, repo, _} = store} = scope, observe: observe} =
        remote

      other_branch = {:github, repo, "main"}
      RemoteFixture.advance(client, other_branch, "notes/final.txt", "main branch")
      RemoteFixture.advance(client, store, "outside.txt", "outside")
      params = %{realm: :target}
      AgentJobs.succeeded(agent, :open, params)

      Files.assert_reply(agent, :create, "draft.txt", %{realm: :source, content: "draft"})

      assert %{commit: copied} =
               AgentJobs.succeeded(agent, :copy, %{path: "draft.txt", to: "draft.txt"})

      assert RemoteFixture.commit(client, repo, copied) == %{
               store: store,
               path: "notes/draft.txt",
               content: "draft"
             }

      path = "final.txt"
      created = mutation(agent, :create, path, Map.put(params, :content, "first"))
      revised = mutation(agent, :edit, path, Map.put(params, :content, "pinned café\n"))
      deleted = mutation(agent, :delete, "draft.txt", params)
      assert RemoteFixture.commit(client, repo, created).content == "first"
      assert RemoteFixture.commit(client, repo, revised).content == "pinned café\n"
      assert RemoteFixture.commit(client, repo, deleted).content == nil
      assert observe.("draft.txt") == {:error, :not_found}

      pinned = %{scope | store: {:github_commit, repo, deleted}}

      reviewer =
        Scenarios.start_agent(instance, AgentJobs.Work, %{
          work: RemoteFixture.session(client, pinned, false)
        })

      review = %{realm: :work}
      AgentJobs.succeeded(reviewer, :open, review)

      stale = revision(agent, path, params)
      RemoteFixture.advance(client, store, "notes/final.txt", "newer")
      update = Map.merge(params, %{content: "stale", revision: stale})
      Files.assert_rejected(agent, :edit_revision, path, :conflict, update)
      assert observe.(path) == {:ok, "newer"}

      before_unrelated = revision(agent, path, params)
      RemoteFixture.advance(client, store, "notes/unrelated.txt", "unrelated")
      update = %{update | content: "latest", revision: before_unrelated}
      latest = mutation(agent, :edit_revision, path, update)
      assert RemoteFixture.commit(client, repo, latest).content == "latest"
      assert observe.("unrelated.txt") == {:ok, "unrelated"}

      Files.assert_reply(reviewer, :read, path, review, %{content: "pinned café\n"})

      Files.assert_rejected(
        reviewer,
        :edit,
        path,
        :permission_denied,
        Map.put(review, :content, "denied")
      )

      Files.assert_rejected(agent, :read, "../outside.txt", :invalid_path, params)

      for option <- [:repository, :branch, :ref] do
        input = params |> Map.merge(%{path: path, content: "redirect"}) |> Map.put(option, "main")
        assert {:ok, %{status: :failed, reply: nil}} = Files.call(agent, :edit, input)
      end

      AgentJobs.succeeded(reviewer, :close, review)
      AgentJobs.succeeded(agent, :close, params)
      assert observe.(path) == {:ok, "latest"}
      assert RemoteFixture.observe(client, store, "outside.txt") == {:ok, "outside"}

      assert RemoteFixture.observe(client, other_branch, "notes/final.txt") ==
               {:ok, "main branch"}

      assert RemoteFixture.commit(client, repo, revised).content == "pinned café\n"
  end

  defp mutation(agent, operation, path, params) do
    assert {:ok, %{status: :committed, reply: %{data: %{commit: commit}}}} =
             Files.call(agent, operation, Map.put(params, :path, path))

    commit
  end

  defp revision(agent, path, params) do
    assert {:ok, %{status: :committed, reply: %{data: %{revision: revision}}}} =
             Files.call(agent, :read_revision, Map.put(params, :path, path))

    revision
  end
end
