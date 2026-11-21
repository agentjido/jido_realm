defmodule Jido.Realm.ProviderVFSTest do
  use ExUnit.Case, async: true

  alias Jido.Realm.Provider.VFS, as: Provider
  alias Jido.VFS
  alias Jido.VFS.Adapter.InMemory

  defmodule ConflictingStore do
    def capture(store) do
      Agent.get_and_update(store, fn {filesystem, faults, attempts} ->
        {VFS.capture(filesystem), {filesystem, faults, attempts + 1}}
      end)
    end

    def apply_edits(store, token, edits) do
      Agent.get_and_update(store, fn
        {filesystem, [fault | rest], attempts} ->
          {{:error, fault}, {filesystem, rest, attempts}}

        {filesystem, [], _} = state ->
          {VFS.apply_edits(filesystem, token, edits), state}
      end)
    end
  end

  setup do
    filesystem = InMemory.configure(name: make_ref())
    start_supervised!({InMemory, filesystem})
    :ok = VFS.create_directory(filesystem, "src/")
    :ok = VFS.write(filesystem, "src/model.txt", "original")
    %{filesystem: filesystem}
  end

  test "only admits a VFS with checked edits and retains directory boundaries", %{filesystem: fs} do
    assert {:error, :unsupported_vfs_binding} = Provider.open(:missing)
    assert {:error, :unsupported_vfs_binding} = Provider.open({String, nil})
    assert {:ok, %{ownership: :borrowed}} = Provider.open(fs)
    assert {:error, :unsupported_file_operation} = Provider.run(fs, :rename, "src", "other")
    assert {:error, :not_a_file} = Provider.run(fs, :read, "src", nil)
    assert {:error, :not_a_file} = Provider.run(fs, :create, "src/model.txt/other", "")
    assert {:error, :not_found} = Provider.run(fs, :create, "missing/other", "")
    assert :ok = Provider.run(fs, :create, "src/other", "hello")
    assert {:ok, "hello"} = VFS.read(fs, "src/other")
  end

  test "retries stale snapshots and stops after eight conflicts", %{filesystem: fs} do
    stale = %VFS.Errors.StaleState{}
    store = start_supervised!({Agent, fn -> {fs, [stale], 0} end})
    wrapped = {ConflictingStore, store}
    assert :ok = Provider.run(wrapped, :edit, "src/model.txt", "updated")
    assert {^fs, [], 2} = Agent.get(store, & &1)

    Agent.update(store, fn _ -> {fs, List.duplicate(stale, 8), 0} end)
    assert {:error, :conflict} = Provider.run(wrapped, :edit, "src/model.txt", "lost")
    assert {^fs, [], 8} = Agent.get(store, & &1)
    assert {:ok, "updated"} = VFS.read(fs, "src/model.txt")

    Agent.update(store, fn _ -> {fs, [%VFS.Errors.AdapterError{}], 0} end)
    assert {:error, :backend_error} = Provider.run(wrapped, :delete, "src/model.txt", nil)
    assert {:ok, "updated"} = VFS.read(fs, "src/model.txt")
  end
end
