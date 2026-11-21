defmodule Jido.Realm.Integration.ArtifactTest do
  use ExUnit.Case, parameterize: [%{kind: :local}, %{kind: :memory}]

  alias Jido.Realm.Artifacts
  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}

  @moduletag :artifact
  @entry "index.html"
  @files %{
    @entry => """
    <!doctype html>
    <link rel="stylesheet" href="report.css">
    <button id="show">Show total</button>
    <output id="total">Hidden</output>
    <script src="report.js"></script>
    """,
    "report.css" => "#total { color: rgb(12, 34, 56); }",
    "report.js" => """
    document.querySelector('#show').addEventListener('click', () => {
      document.querySelector('#total').textContent = 'Total: 42';
    });
    document.body.dataset.origin = self.origin;
    """
  }

  setup context do
    store = start_supervised!({Artifacts, viewers: [:reviewer], max_artifacts: 2})
    grants = Map.get(context, :grants, [:open, :close, :read, :write, :publish])
    observer = self()

    hook = fn operation, path, _, run ->
      if operation == :read, do: send(observer, {:artifact_source_read, path})
      run.()
    end

    binding =
      {BindingFixture,
       kind: context.kind, mode: :owned, grants: grants, hook: hook, presenter: {Artifacts, store}}

    %{agent: agent, placements: %{work: work}} =
      Scenarios.prepare(context, AgentJobs.Work, [work: binding], context.kind)

    AgentJobs.succeeded(agent, :open, %{realm: :work})
    %{agent: agent, work: work, store: store}
  end

  test "08.03 delivers only the selected page and assets to its reviewer", ctx do
    write_report(ctx.agent)
    ctx.work.seed.("private.txt", "private workspace notes")
    assert %{media_type: "text/html; charset=utf-8"} = artifact = publish(ctx)

    for {path, content} <- @files do
      assert {:ok, %{content: ^content}} = Artifacts.read(ctx.store, :reviewer, artifact.id, path)
      assert {:error, :not_found} = Artifacts.read(ctx.store, :stranger, artifact.id, path)
    end

    assert {:error, :not_found} = Artifacts.read(ctx.store, :reviewer, artifact.id, "private.txt")
  end

  test "08.03 versions survive source edits and deletion of the owned work tree", ctx do
    write_report(ctx.agent)
    first = publish(ctx)
    Files.assert_reply(ctx.agent, :edit, "report.js", %{realm: :work, content: "// revised"})
    second = publish(ctx)
    refute first.id == second.id
    refute first.revision == second.revision
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})

    assert ctx.work.observe.("report.js") == {:error, :not_found}

    assert {:ok, %{content: content}} =
             Artifacts.read(ctx.store, :reviewer, first.id, "report.js")

    assert content == @files["report.js"]

    assert {:ok, %{content: "// revised"}} =
             Artifacts.read(ctx.store, :reviewer, second.id, "report.js")
  end

  @tag grants: [:open, :close, :read, :write]
  test "08.03 requires a publish grant even when the agent authored the report", ctx do
    write_report(ctx.agent)
    AgentJobs.rejected(ctx.agent, :publish, :permission_denied, request())
    refute_received {:artifact_source_read, _}
    assert ctx.work.observe.(@entry) == {:ok, @files[@entry]}
  end

  @tag grants: [:open, :close, :write, :publish]
  test "08.03 requires a read grant to collect output", ctx do
    write_report(ctx.agent)
    AgentJobs.rejected(ctx.agent, :publish, :permission_denied, request())
    refute_received {:artifact_source_read, _}
    assert ctx.work.observe.(@entry) == {:ok, @files[@entry]}
  end

  test "08.03 a missing asset consumes no publication slot and can be retried", ctx do
    ctx.work.seed.(@entry, @files[@entry])
    AgentJobs.rejected(ctx.agent, :publish, :not_found, request())
    AgentJobs.rejected(ctx.agent, :publish, :not_found, request())

    for {path, bytes} <- Map.delete(@files, @entry), do: ctx.work.seed.(path, bytes)
    assert publish(ctx).entrypoint == @entry
    assert publish(ctx).entrypoint == @entry
  end

  test "08.03 validates the complete bundle before reading any file", ctx do
    write_report(ctx.agent)

    for paths <- [
          [@entry, "../private.txt"],
          [@entry, "%2e%2e/report.js"],
          [@entry, @entry],
          ["report.js"],
          [@entry, ".jido-realm-draft.css"]
        ] do
      AgentJobs.rejected(ctx.agent, :publish, :invalid_artifact_bundle, request(paths))
    end

    refute_received {:artifact_source_read, _}
  end

  test "08.03 revokes the page and each asset without removing the work files", ctx do
    write_report(ctx.agent)
    %{id: id} = publish(ctx)
    assert :ok = Artifacts.revoke(ctx.store, id)

    for path <- Map.keys(@files) do
      assert {:error, :not_found} = Artifacts.read(ctx.store, :reviewer, id, path)
      assert ctx.work.observe.(path) == {:ok, @files[path]}
    end
  end

  test "08.03 enforces output bounds and accepts another version after revocation", ctx do
    write_report(ctx.agent)
    ctx.work.seed.("oversized.txt", :binary.copy("x", 1_048_577))

    AgentJobs.rejected(
      ctx.agent,
      :publish,
      :artifact_too_large,
      request([@entry, "oversized.txt"])
    )

    first = publish(ctx)
    second = publish(ctx)
    assert first.revision == second.revision
    AgentJobs.rejected(ctx.agent, :publish, :artifact_capacity, request())
    assert {:ok, _} = Artifacts.read(ctx.store, :reviewer, second.id)

    assert :ok = Artifacts.revoke(ctx.store, first.id)
    assert publish(ctx).revision == second.revision
  end

  @tag :browser
  test "08.03 a reviewer opens an isolated artifact and operates the report", ctx do
    write_report(ctx.agent)
    %{id: id} = publish(ctx)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})

    url = Jido.Realm.Conformance.ArtifactBrowser.serve(ctx.store, id)

    assert {"artifact loaded, styled, and interactive\n", 0} =
             Jido.Realm.Conformance.ArtifactBrowser.review(url)
  end

  defp write_report(agent) do
    for {path, content} <- @files do
      Files.assert_reply(agent, :create, path, %{realm: :work, content: content})
    end
  end

  defp publish(ctx), do: AgentJobs.succeeded(ctx.agent, :publish, request())

  defp request(paths \\ Map.keys(@files)),
    do: %{realm: :work, path: @entry, paths: paths}
end
