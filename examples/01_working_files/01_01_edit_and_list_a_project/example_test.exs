Code.require_file("../../05_lifecycle/support.exs", __DIR__)
Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.EditProjectTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Entry, Error, Execution}
  alias Jido.Realm.Host.Examples.EditProject
  import Jido.Realm.Host.Examples.LifecycleSupport, only: [configure: 1]

  @draft "Draft for review\n"

  setup %{tmp_dir: root}, do: configure(root)

  test "memory matches the portable file operation contract" do
    check_project(:memory)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to test the same file calls on Docker"
  end

  test "Docker matches the portable file operation contract" do
    check_project(:docker)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to create links in the Docker test tree"
  end

  test "moves refuse a symbolic link and keep distinct hard-link names" do
    assert {:ok, workspace} = Host.open(profile: :docker)

    try do
      assert :ok = Host.write(workspace, "data.txt", @draft)

      assert {:ok, %Execution{exit_status: 0}} =
               Host.run(workspace, ["ln", "data.txt", "copy.txt"])

      assert :ok = Host.move(workspace, "copy.txt", "moved.txt")
      assert {:error, %Error{code: :not_found}} = Host.read(workspace, "copy.txt")
      assert {:ok, @draft} = Host.read(workspace, "data.txt")
      assert {:ok, @draft} = Host.read(workspace, "moved.txt")

      assert {:ok, %Execution{exit_status: 0}} =
               Host.run(workspace, ["ln", "-s", "data.txt", "link.txt"])

      assert {:error, %Error{code: :symlink_path, operation: :move}} =
               Host.move(workspace, "link.txt", "new.txt")

      assert {:error, %Error{code: :symlink_path, operation: :move}} =
               Host.move(workspace, "data.txt", "link.txt")

      assert {:ok, @draft} = Host.read(workspace, "data.txt")
      assert {:error, %Error{code: :not_found}} = Host.read(workspace, "new.txt")
    after
      assert :ok = Host.close(workspace)
    end
  end

  defp check_project(profile) do
    assert {:ok, workspace} = Host.open(profile: profile)

    snapshot =
      try do
        assert {:ok, @draft, [%Entry{path: "project/review/draft.txt", kind: :file, size: 17}]} =
                 EditProject.prepare_review(workspace, ["Draft ", "for review\n"])

        assert {:error, %Error{code: :not_found}} =
                 Host.read(workspace, "project/inbox/draft.txt")

        assert {:error, %Error{code: :not_found}} = Host.list(workspace, "project/inbox")
        assert {:error, %Error{code: :not_found}} = Host.delete(workspace, "project/inbox")
        assert :ok = Host.mkdir(workspace, "project/review")
        assert {:ok, @draft} = Host.read(workspace, "project/review/draft.txt")

        assert {:error, %Error{code: :directory_not_empty}} =
                 Host.delete(workspace, "project/review")

        assert {:error, %Error{code: :is_directory}} = Host.read(workspace, "project/review")

        assert {:error, %Error{code: :is_directory}} =
                 Host.write(workspace, "project/review", "X")

        assert {:error, %Error{code: :not_directory}} =
                 Host.list(workspace, "project/review/draft.txt")

        assert {:error, %Error{code: :not_directory}} =
                 Host.mkdir(workspace, "project/review/draft.txt")

        assert :ok = Host.mkdir(workspace, "project/review/empty")
        assert :ok = Host.move(workspace, "project/review", "project/published")
        assert {:error, %Error{code: :not_found}} = Host.list(workspace, "project/review")
        assert {:ok, []} = Host.list(workspace, "project/published/empty")

        assert {:ok, %Execution{status: :exited, exit_status: 0, output: @draft}} =
                 Host.run(workspace, ["cat", "draft.txt"], cwd: "project/published")

        check_move_errors(workspace)
        assert {:ok, %{kind: "snapshot"} = snapshot} = Host.save(workspace)
        snapshot
      after
        assert :ok = Host.close(workspace)
      end

    check_read_only(profile, snapshot)
  end

  defp check_move_errors(workspace) do
    source = "project/published/draft.txt"
    destination = "project/published/other.txt"
    assert :ok = Host.write(workspace, destination, "Separate file\n")

    assert {:error, %Error{code: :already_exists, operation: :move}} =
             Host.move(workspace, source, destination)

    assert {:error, %Error{code: :already_exists, operation: :move}} =
             Host.move(workspace, source, source)

    assert {:error, %Error{code: :not_found, operation: :move}} =
             Host.move(workspace, "project/missing", destination)

    assert {:error, %Error{code: :not_found, operation: :move}} =
             Host.move(workspace, source, "project/missing/new.txt")

    for {from, to} <- [
          {source, "../outside.txt"},
          {"/absolute", destination},
          {".", "elsewhere"},
          {"project/published", "project/published/empty/inside"}
        ] do
      assert {:error, %Error{code: :invalid_input, operation: :move}} =
               Host.move(workspace, from, to)
    end

    assert {:ok, @draft} = Host.read(workspace, source)
    assert {:ok, "Separate file\n"} = Host.read(workspace, destination)
    assert :ok = Host.delete(workspace, destination)
  end

  defp check_read_only(profile, snapshot) do
    profiles = Application.fetch_env!(:jido_realm, :profiles)
    restricted = %{Map.fetch!(profiles, profile) | policy: :read_only}
    Application.put_env(:jido_realm, :profiles, Map.put(profiles, :review, restricted))

    assert {:ok, workspace} = Host.open(profile: :review, from: snapshot)

    try do
      assert {:ok, @draft} = Host.read(workspace, "project/published/draft.txt")

      assert {:error, %Error{code: :policy_denied, operation: :move}} =
               Host.move(
                 workspace,
                 "project/published/draft.txt",
                 "project/published/new.txt"
               )
    after
      assert :ok = Host.close(workspace)
    end
  end
end
