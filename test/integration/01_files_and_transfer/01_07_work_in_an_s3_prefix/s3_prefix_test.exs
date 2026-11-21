defmodule Jido.Realm.Integration.S3PrefixTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, RemoteFixture}

  realm_case "01.07 organize and reconcile files in a scoped S3 prefix",
    agent: AgentJobs.Pair,
    evidence: :controlled_transport,
    cases: [
      s3_prefix: [
        source: {RemoteFixture, store: {:s3, "test-bucket"}, prefix: "notes"},
        target: {BindingFixture, kind: :local, mode: :static}
      ]
    ] do
    %{agent: agent, placements: %{source: remote}, observe: %{target: local}} ->
      %{client: client, scope: %{store: store}, observe: observe} = remote
      sentinel = "notes-extra/sentinel.txt"
      :ok = RemoteFixture.advance(client, store, sentinel, "outside")
      assert :reconcile in AgentJobs.succeeded(agent, :open, %{realm: :source}).capabilities

      params = %{realm: :source}
      path = "note.txt"
      bytes = "A note from the agent café\n"
      job = Map.merge(params, %{path: "draft.txt", to: path, text: bytes})
      assert %{path: ^path} = AgentJobs.succeeded(agent, :organize, job)
      AgentJobs.succeeded(agent, :copy, %{path: path, to: "review.txt"})
      assert local.("review.txt") == {:ok, bytes}
      assert observe.(path) == {:ok, bytes}
      assert observe.("draft.txt") == {:error, :not_found}

      Files.assert_rejected(
        agent,
        :create,
        path,
        :already_exists,
        Map.put(params, :content, "duplicate")
      )

      assert {:ok, %{status: :committed, reply: %{data: %{revision: revision}}}} =
               Files.call(agent, :read_revision, Map.put(params, :path, path))

      :ok = RemoteFixture.advance(client, store, "notes/note.txt", "new version")
      stale = Map.put(params, :revision, revision)

      Files.assert_rejected(
        agent,
        :edit_revision,
        path,
        :conflict,
        Map.put(stale, :content, "stale")
      )

      Files.assert_rejected(agent, :delete_revision, path, :conflict, stale)
      assert observe.(path) == {:ok, "new version"}

      RemoteFixture.lose_reply(client, path)

      assert {:ok, %{status: :failed, error: %{details: %{reason: {:unknown, request_id}}}}} =
               Files.call(agent, :edit, Map.merge(params, %{path: path, content: "applied"}))

      assert observe.(path) == {:ok, "applied"}
      :ok = RemoteFixture.advance(client, store, "notes/note.txt", "newest")
      count = RemoteFixture.count(client)

      Files.assert_reply(agent, :reconcile, path, Map.put(params, :request_id, request_id), %{
        outcome: :applied
      })

      assert RemoteFixture.count(client) == count
      assert observe.(path) == {:ok, "newest"}
      Files.assert_rejected(agent, :read, "../#{sentinel}", :invalid_path, params)

      for option <- [:bucket, :prefix] do
        input =
          params |> Map.merge(%{path: path, content: "redirect"}) |> Map.put(option, "other")

        assert {:ok, %{status: :failed, reply: nil}} = Files.call(agent, :edit, input)
      end

      AgentJobs.succeeded(agent, :close, params)
      Files.assert_rejected(agent, :read, path, :session_closed, params)
      assert observe.(path) == {:ok, "newest"}
      assert RemoteFixture.observe(client, store, sentinel) == {:ok, "outside"}
  end
end
