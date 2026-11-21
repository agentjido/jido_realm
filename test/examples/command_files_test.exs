defmodule Jido.Realm.Host.CommandFilesTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  alias Jido.Realm.Host
  alias Jido.Realm.Host.Sandbox

  test "Sandbox checks a directory revision before it starts a command or service" do
    {:ok, sandbox} = Sandbox.open()
    on_exit(fn -> Sandbox.destroy(sandbox) end)
    :ok = Sandbox.write(sandbox, "work/input", "one")
    {:ok, view} = Sandbox.file_view(sandbox, "work")

    assert {:ok, %{output: "one", files: ^view, exit_status: 0}} =
             Sandbox.exec(sandbox, "/bin/cat", ["input"], dir: "./work/.", files: view)

    :ok = Sandbox.write(sandbox, "work/input", "two")

    assert {:error, :stale_file_view} =
             Sandbox.exec(sandbox, "/usr/bin/touch", ["marker"], dir: "work", files: view)

    assert {:error, :enoent} = Sandbox.read(sandbox, "work/marker")

    assert {:error, :stale_file_view} =
             Sandbox.start_service(sandbox, %{kind: :beam, dir: "work", files: view})

    {:ok, current} = Sandbox.file_view(sandbox, "work")
    assert current.revision != view.revision

    assert {:ok, %{output: "two", files: ^current}} =
             Sandbox.exec(sandbox, "/bin/cat", ["input"], dir: "work", files: current)
  end

  test "memory and Sandbox files remain distinct, with explicit evidence" do
    {:ok, workspace} = Host.open()
    {:ok, sandbox} = Sandbox.open()

    on_exit(fn ->
      Host.close(workspace)
      Sandbox.destroy(sandbox)
    end)

    :ok = Host.write(workspace, "/input", "memory")
    :ok = Sandbox.write(sandbox, "input", "disk")
    {:ok, memory} = Host.file_view(workspace)
    {:ok, disk} = Sandbox.file_view(sandbox)

    assert {:ok, %{output: "memory", files: ^memory}} =
             Host.run(workspace, "cat /input", files: memory)

    assert {:ok, %{output: "disk", files: ^disk}} =
             Sandbox.exec(sandbox, "/bin/cat", ["input"], files: disk)

    assert {:error, :stale_file_view} =
             Sandbox.exec(sandbox, "/bin/cat", ["input"], files: memory)
  end
end
