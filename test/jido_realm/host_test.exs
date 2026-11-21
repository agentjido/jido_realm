defmodule Jido.Realm.HostTest do
  use ExUnit.Case, async: false

  alias Jido.Realm.Host

  @moduletag :contract

  setup do
    {:ok, workspace} = Host.open()
    Process.put(:workspace_under_test, workspace)

    on_exit(fn ->
      case Process.get(:workspace_under_test) do
        %Jido.Realm.Host.Handle{} = current ->
          _ = Host.close(current)
          :ok

        _ ->
          :ok
      end
    end)

    {:ok, workspace: workspace}
  end

  describe "artifact operations" do
    test "writes, reads, lists, and deletes files", %{workspace: workspace} do
      :ok = Host.write(workspace, "/hello.txt", "Hello, World!")
      Process.put(:workspace_under_test, workspace)

      assert {:ok, "Hello, World!"} = Host.read(workspace, "/hello.txt")

      assert {:ok, [%Jido.Realm.Host.Entry{path: "/hello.txt"}]} = Host.list(workspace, "/")

      :ok = Host.delete(workspace, "/hello.txt")
      Process.put(:workspace_under_test, workspace)

      assert {:error, %Jido.Realm.Host.Error{code: :not_found}} =
               Host.read(workspace, "/hello.txt")
    end

    test "creates and uses directories", %{workspace: workspace} do
      :ok = Host.mkdir(workspace, "/artifacts")
      :ok = Host.write(workspace, "/artifacts/note.md", "# Note")
      Process.put(:workspace_under_test, workspace)

      assert {:ok, [%Jido.Realm.Host.Entry{path: "/artifacts/note.md"}]} =
               Host.list(workspace, "/artifacts")

      assert {:ok, "# Note"} = Host.read(workspace, "/artifacts/note.md")
    end
  end

  describe "capture and checked replacement" do
    test "restores workspace tree to prior state", %{workspace: workspace} do
      :ok = Host.write(workspace, "/original.txt", "original")
      :ok = Host.mkdir(workspace, "/nested")
      :ok = Host.write(workspace, "/nested/a.txt", "a")

      {:ok, snapshot_id, _} = Host.capture(workspace)

      :ok = Host.delete(workspace, "/original.txt")
      :ok = Host.write(workspace, "/nested/new.txt", "new")
      Process.put(:workspace_under_test, workspace)

      assert {:error, %Jido.Realm.Host.Error{code: :not_found}} =
               Host.read(workspace, "/original.txt")

      assert {:ok, "new"} = Host.read(workspace, "/nested/new.txt")

      {:ok, _, revision} = Host.capture(workspace)
      {:ok, _} = Host.replace(workspace, snapshot_id, expected: revision)
      Process.put(:workspace_under_test, workspace)

      assert {:ok, "original"} = Host.read(workspace, "/original.txt")
      assert {:ok, "a"} = Host.read(workspace, "/nested/a.txt")

      assert {:error, %Jido.Realm.Host.Error{code: :not_found}} =
               Host.read(workspace, "/nested/new.txt")
    end

    test "rejects an invalid capture", %{workspace: workspace} do
      assert {:error, %Jido.Realm.Host.Error{code: :invalid_input}} =
               Host.replace(workspace, "snap-404", expected: :invalid)
    end
  end

  describe "shell session integration" do
    test "runs commands in workspace session", %{workspace: workspace} do
      assert {:ok, %{output: "/\n"}} = Host.run(workspace, "pwd")
      Process.put(:workspace_under_test, workspace)

      assert {:ok, %{session: :running}} = Host.info(workspace)

      assert {:ok, %{output: output}} = Host.run(workspace, "write /from_shell.txt hi")
      assert output =~ "wrote"
      Process.put(:workspace_under_test, workspace)

      assert {:ok, "hi"} = Host.read(workspace, "/from_shell.txt")
    end
  end
end
