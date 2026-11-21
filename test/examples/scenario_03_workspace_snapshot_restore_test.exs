defmodule Jido.Realm.Host.Integration.Scenario03WorkspaceSnapshotRestoreTest do
  use ExUnit.Case, async: false
  alias Jido.Realm.Host
  @moduletag :integration

  test "memory capture restores a complete tree through checked replacement" do
    {:ok, ws} = Host.open()

    try do
      :ok = Host.write(ws, "/original", "saved")
      :ok = Host.mkdir(ws, "/empty")
      {:ok, capture, _} = Host.capture(ws)
      :ok = Host.delete(ws, "/original")
      :ok = Host.write(ws, "/new", "new")
      {:ok, _, revision} = Host.capture(ws)
      {:ok, _} = Host.replace(ws, capture, expected: revision)
      assert {:ok, "saved"} = Host.read(ws, "/original")
      assert {:error, %Jido.Realm.Host.Error{code: :not_found}} = Host.read(ws, "/new")
      assert {:ok, []} = Host.list(ws, "/empty")
    after
      Host.close(ws)
    end
  end

  @tag :tmp_dir
  test "local storage refuses an atomic capture instead of walking live files", %{tmp_dir: dir} do
    {:ok, ws} = Host.open(adapter: Jido.VFS.Adapter.Local, adapter_opts: [prefix: dir])

    try do
      assert {:error, %Jido.Realm.Host.Error{code: :unsupported_capability}} =
               Host.capture(ws)
    after
      Host.close(ws)
    end
  end
end
