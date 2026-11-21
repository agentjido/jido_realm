Code.require_file("../../05_lifecycle/support.exs", __DIR__)

defmodule Jido.Realm.Host.Examples.SaveScratchTreeTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Realm.Host
  alias Jido.Realm.Host.Error
  alias Jido.Realm.Host.Examples.LifecycleSupport

  setup %{tmp_dir: root} do
    store = Path.join(root, "snapshots")
    LifecycleSupport.configure(store)
    %{memory: memory, docker: docker} = Application.fetch_env!(:jido_realm, :profiles)
    scratch = %{memory | policy: [:read, :write, :save]}
    review = %{memory | policy: :read_only}

    Application.put_env(:jido_realm, :profiles, %{
      scratch: scratch,
      review: review,
      docker_review: %{docker | policy: :read_only},
      other: %{review | store: "other"},
      probe: %{scratch | store: "probe"}
    })

    Application.put_env(:jido_realm, :stores, %{
      "reports" => store,
      "other" => store,
      "probe" => Path.join(root, "probe")
    })

    %{store: store}
  end

  test "the reviewer can retain the exact snapshot after the scratch workspace closes", %{
    store: store
  } do
    {:ok, snapshot} =
      in_workspace(:scratch, fn workspace ->
        assert :ok = Host.write(workspace, "report.txt", "candidate\n")
        assert {:ok, snapshot} = Host.save(workspace)
        assert {:ok, ^snapshot} = Host.save(workspace)
        assert :ok = Host.write(workspace, "report.txt", "unsaved edit\n")
        {:ok, snapshot}
      end)

    reference = snapshot |> Jason.encode!() |> Jason.decode!()
    assert [snapshot.digest] == File.ls!(store)

    in_workspace(:review, [from: reference], fn reviewer ->
      assert {:ok, "candidate\n"} = Host.read(reviewer, "report.txt")

      assert {:error, %Error{code: :policy_denied, details: %{action: :write}}} =
               Host.write(reviewer, "report.txt", "overwrite\n")

      assert {:error, %Error{code: :policy_denied, details: %{action: :save}}} =
               Host.save(reviewer)
    end)

    assert {:error, %Error{code: :policy_denied, details: %{action: :import}}} =
             Host.open(profile: :other, from: reference)
  end

  test "failed publication leaves the earlier snapshot and a live workspace for retry", %{
    store: store
  } do
    # Use the public API in a separate store to find the next content digest.
    assert {:ok, %{digest: next_digest}} = save_report(:probe, "next candidate\n")

    in_workspace(:scratch, fn workspace ->
      assert :ok = Host.write(workspace, "report.txt", "earlier candidate\n")
      assert {:ok, earlier} = Host.save(workspace)
      assert :ok = Host.write(workspace, "report.txt", "next candidate\n")
      blocked_path = Path.join(store, next_digest)
      File.mkdir!(blocked_path)

      assert {:error, %Error{operation: :save, code: :snapshot_store_unavailable}} =
               Host.save(workspace)

      assert Enum.sort(File.ls!(store)) == Enum.sort([earlier.digest, next_digest])
      assert {:ok, %{phase: :ready}} = Host.info(workspace)
      assert {:ok, "next candidate\n"} = Host.read(workspace, "report.txt")

      assert {:error, %Error{code: :invalid_snapshot}} =
               Host.open(profile: :review, from: %{earlier | digest: next_digest})

      assert_report(:review, earlier, "earlier candidate\n")
      File.rmdir!(blocked_path)
      assert {:ok, %{digest: ^next_digest} = retried} = Host.save(workspace)
      assert_report(:review, retried, "next candidate\n")
      assert_report(:review, earlier, "earlier candidate\n")
    end)
  end

  test "a reference resolves only to a regular bundle inside the configured store", %{
    tmp_dir: root,
    store: store
  } do
    assert {:ok, snapshot} = save_report(:scratch, "reviewed\n")
    path = Path.join(store, snapshot.digest)
    outside = Path.join(root, "outside")
    File.rename!(path, outside)
    File.ln_s!(outside, path)

    assert {:error, %Error{code: :invalid_snapshot}} =
             Host.open(profile: :review, from: snapshot)

    File.rm!(path)
    assert {:error, %Error{code: :not_found}} = Host.open(profile: :review, from: snapshot)

    File.rmdir!(store)
    File.write!(store, "blocked store")

    assert {:error, %Error{code: :snapshot_store_unavailable}} =
             Host.open(profile: :review, from: snapshot)

    File.rm!(store)
    File.mkdir!(store)
    File.rename!(outside, path)
    assert_report(:review, snapshot, "reviewed\n")
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to review the stored tree on Docker"
  end

  test "Docker can review the same saved memory tree" do
    assert {:ok, snapshot} = save_report(:scratch, "reviewed on Docker\n")
    assert_report(:docker_review, snapshot, "reviewed on Docker\n")
  end

  defp save_report(profile, content) do
    in_workspace(profile, fn workspace ->
      assert :ok = Host.write(workspace, "report.txt", content)
      Host.save(workspace)
    end)
  end

  defp assert_report(profile, reference, content) do
    in_workspace(profile, [from: reference], fn workspace ->
      assert {:ok, ^content} = Host.read(workspace, "report.txt")
    end)
  end

  defp in_workspace(profile, options \\ [], action) do
    assert {:ok, workspace} = Host.open([profile: profile] ++ options)

    try do
      action.(workspace)
    after
      assert :ok = Host.close(workspace)
    end
  end
end
