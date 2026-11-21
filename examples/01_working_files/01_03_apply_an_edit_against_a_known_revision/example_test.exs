Code.require_file("../../05_lifecycle/support.exs", __DIR__)
Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.EditKnownRevisionTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Entry, Error, Execution}
  alias Jido.Realm.Host.Examples.EditKnownRevision
  import Jido.Realm.Host.Examples.LifecycleSupport, only: [configure: 1]

  @path "draft.txt"
  @original "Original\n"
  @command_edit "Reviewed\n"

  setup %{tmp_dir: root}, do: configure(root)

  test "memory rejects stale edits and checks revisions after commands" do
    check_revisions(:memory)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to check revisions on Docker"
  end

  test "Docker rejects stale edits and checks revisions after commands" do
    check_revisions(:docker)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to check native file types and metadata"
  end

  test "native edits replace the specified hard link and preserve its mode" do
    assert {:ok, workspace} = Host.open(profile: :docker)

    try do
      assert :ok = Host.write(workspace, @path, @original)
      assert {:ok, %Execution{exit_status: 0}} = Host.run(workspace, ["chmod", "700", @path])

      assert {:ok, %Execution{exit_status: 0}} =
               Host.run(workspace, ["ln", @path, "copy.txt"])

      assert {:ok, @original, revision} = Host.read(workspace, "copy.txt", revision: true)
      assert :ok = Host.write(workspace, "copy.txt", @command_edit, expected: revision)
      assert {:ok, @original} = Host.read(workspace, @path)
      assert {:ok, @command_edit} = Host.read(workspace, "copy.txt")

      assert {:ok, [%Entry{path: "copy.txt", mode: :executable}, %Entry{path: @path}]} =
               Host.list(workspace)

      assert {:ok, %Execution{exit_status: 0}} =
               Host.run(workspace, ["sh", "-c", "ln -s draft.txt link.txt && mkfifo pipe"])

      assert {:error, %Error{code: :symlink_path}} =
               Host.write(workspace, "link.txt", "Rejected", expected: revision)

      assert {:error, %Error{code: :unsupported_capability}} =
               Host.read(workspace, "pipe", revision: true)

      assert {:error, %Error{code: :unsupported_capability}} =
               Host.write(workspace, "pipe", "Rejected", expected: revision)
    after
      assert :ok = Host.close(workspace)
    end
  end

  defp check_revisions(profile) do
    assert {:ok, workspace} = Host.open(profile: profile)

    snapshot =
      try do
        assert :ok = Host.write(workspace, @path, @original)
        check_concurrent_edits(workspace)

        assert {:ok, _, before_command} = Host.read(workspace, @path, revision: true)
        assert :ok = Host.write(workspace, "incoming.txt", @command_edit)

        assert {:ok, %Execution{exit_status: 0}} =
                 Host.run(workspace, ["cp", "incoming.txt", @path])

        assert {:error, %Error{code: :stale_revision}} =
                 Host.write(workspace, @path, "Rejected", expected: before_command)

        assert {:ok, @command_edit, current} = Host.read(workspace, @path, revision: true)

        assert {:error, %Error{code: :invalid_input}} =
                 Host.write(workspace, @path, "Rejected", expected: "invalid")

        assert {:error, %Error{code: :invalid_input}} =
                 Host.write(workspace, "../draft.txt", "Rejected", expected: current)

        assert {:ok, snapshot} = Host.save(workspace)
        assert :ok = Host.delete(workspace, @path)

        assert {:error, %Error{code: :stale_revision}} =
                 Host.write(workspace, @path, "Rejected", expected: current)

        assert {:error, %Error{code: :not_found}} =
                 Host.read(workspace, @path, revision: true)

        assert :ok = Host.mkdir(workspace, @path)

        assert {:error, %Error{code: :is_directory}} =
                 Host.write(workspace, @path, "Rejected", expected: current)

        assert {:ok, []} = Host.list(workspace, @path)
        snapshot
      after
        assert :ok = Host.close(workspace)
      end

    check_policy(profile, snapshot)
  end

  defp check_concurrent_edits(workspace) do
    reviewer = self()
    barrier = make_ref()

    edits =
      for text <- ["Editor A\n", "Editor B\n"] do
        task =
          Task.async(fn ->
            EditKnownRevision.edit(workspace, @path, fn current ->
              send(reviewer, {self(), :read, current})

              receive do
                ^barrier -> text
              end
            end)
          end)

        {task, text}
      end

    for {%Task{pid: pid}, _} <- edits do
      assert_receive {^pid, :read, @original}, 5_000
    end

    for {task, _} <- edits, do: send(task.pid, barrier)

    results = Enum.map(edits, fn {task, text} -> {Task.await(task, 10_000), text} end)
    assert [winner] = for({:ok, text} <- results, do: text)

    assert [%Error{code: :stale_revision, operation: :write}] =
             for({{:error, error}, _} <- results, do: error)

    assert {:ok, ^winner} = Host.read(workspace, @path)

    assert :ok = EditKnownRevision.edit(workspace, @path, &[&1, "Follow-up\n"])
    assert {:ok, winner <> "Follow-up\n"} == Host.read(workspace, @path)
  end

  defp check_policy(profile, snapshot) do
    profiles = Application.fetch_env!(:jido_realm, :profiles)
    read_only = %{Map.fetch!(profiles, profile) | policy: :read_only}
    Application.put_env(:jido_realm, :profiles, Map.put(profiles, :reader, read_only))

    assert {:ok, workspace} = Host.open(profile: :reader, from: snapshot)

    try do
      assert {:ok, @command_edit, revision} = Host.read(workspace, @path, revision: true)

      assert {:error, %Error{code: :policy_denied}} =
               Host.write(workspace, @path, "Rejected", expected: revision)
    after
      assert :ok = Host.close(workspace)
    end
  end
end
