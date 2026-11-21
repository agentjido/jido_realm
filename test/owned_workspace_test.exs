defmodule Jido.Realm.Host.OwnedWorkspaceTest do
  use ExUnit.Case, async: false
  alias Jido.Realm.Host

  test "one owned environment shares shell edits and checked captures" do
    {:ok, ws} = Host.open()

    try do
      {:ok, fs} = Host.filesystem(ws)
      {:ok, shell} = Host.shell(ws)
      assert {:ok, ^shell} = Host.shell(ws)
      {:ok, before, token} = Host.capture(ws)
      assert :ok = Jido.Shell.Agent.write_file(shell, "/source", "new")

      assert {:error, %Jido.Realm.Host.Error{code: :stale_revision}} =
               Host.replace(ws, before, expected: token)

      assert {:ok, "new"} = Jido.VFS.read(fs, "source")
      {:ok, current, token} = Host.capture(ws)
      assert {:ok, _} = Host.replace(ws, before, expected: token)
      assert :ok = Host.stop_session(ws)
      assert {:ok, :missing} = Jido.VFS.file_exists(fs, "source")
      :ok = Host.close(ws)
      assert {:ok, "new"} = Jido.VFS.read(current, "source")
      assert :ok = Host.close(ws)
      assert {:error, %Jido.Realm.Host.Error{code: :closed}} = Host.filesystem(ws)
    after
      Host.close(ws)
    end
  end

  test "owner exit stops commands and storage without deleting captures" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, ws} = Host.open()
        {:ok, fs} = Host.filesystem(ws)
        {:ok, shell} = Host.shell(ws)
        :ok = Jido.VFS.write(fs, "source", "saved")
        {:ok, saved, _} = Host.capture(ws)
        send(parent, {:workspace, ws, fs, shell, saved})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:workspace, ws, {_adapter, config}, shell, saved}
    storage = GenServer.whereis(Jido.VFS.Registry.via(Jido.VFS.Adapter.InMemory, config.name))
    {:ok, session} = Jido.Shell.ShellSession.lookup(shell)
    refs = Enum.map([ws.lifetime, storage, session], &Process.monitor/1)

    {:ok, :accepted} =
      Jido.Shell.ShellSessionServer.run_command(shell, "sleep 30; write /late bad")

    {:ok, state} = Jido.Shell.ShellSessionServer.get_state(shell)
    task = state.current_command.task
    send(owner, :stop)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 2_000)
    refute Process.alive?(task)
    assert {:ok, "saved"} = Jido.VFS.read(saved, "source")
    assert Jido.Shell.VFS.list_mounts(ws.id) == []
  end

  test "failed session startup releases storage and routes" do
    name = make_ref()

    assert {:error, _} =
             Host.open(
               id: "failed-owned-start",
               adapter_opts: [name: name],
               start_session: true,
               session_opts: [backend: {NotABackend, %{}}]
             )

    assert GenServer.whereis(Jido.VFS.Registry.via(Jido.VFS.Adapter.InMemory, name)) == nil
    assert Jido.Shell.VFS.list_mounts("failed-owned-start") == []
  end

  test "storage failure closes the environment instead of restarting it empty" do
    {:ok, ws} = Host.open()
    {:ok, {_adapter, config}} = Host.filesystem(ws)
    {:ok, shell} = Host.shell(ws)
    {:ok, session} = Jido.Shell.ShellSession.lookup(shell)
    ref = Process.monitor(ws.lifetime)
    session_ref = Process.monitor(session)
    storage = GenServer.whereis(Jido.VFS.Registry.via(Jido.VFS.Adapter.InMemory, config.name))
    Process.exit(storage, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}, 2_000
    assert_receive {:DOWN, ^session_ref, :process, _, _}, 2_000
    assert {:error, %Jido.Realm.Host.Error{code: :closed}} = Host.filesystem(ws)
  end

  test "captures refuse multiple mounts" do
    {:ok, ws} = Host.open()

    try do
      :ok = Jido.Shell.VFS.mount(ws.id, "/scratch", Jido.VFS.Adapter.InMemory, name: make_ref())

      assert {:error, %Jido.Realm.Host.Error{code: :unsupported_capability}} =
               Host.capture(ws)
    after
      Host.close(ws)
    end
  end

  test "closed handles cannot access a new workspace with the same ID" do
    {:ok, old} = Host.open(id: "reused-workspace")
    :ok = Host.close(old)
    {:ok, fresh} = Host.open(id: "reused-workspace")

    try do
      :ok = Host.write(fresh, "/keep", "safe")
      assert {:error, %Jido.Realm.Host.Error{code: :closed}} = Host.write(old, "/keep", "bad")
      assert {:error, %Jido.Realm.Host.Error{code: :closed}} = Host.read(old, "/keep")
      assert {:error, %Jido.Realm.Host.Error{code: :closed}} = Host.list(old)
      assert {:error, %Jido.Realm.Host.Error{code: :closed}} = Host.delete(old, "/keep")
      assert {:error, %Jido.Realm.Host.Error{code: :closed}} = Host.mkdir(old, "/bad")
      assert {:ok, "safe"} = Host.read(fresh, "/keep")
    after
      Host.close(fresh)
    end
  end

  test "reused session names do not transfer ownership" do
    {:ok, a} = Host.open()
    {:ok, b} = Host.open()
    id = "reused-owned-session"

    try do
      {:ok, _} = Host.start_session(a, session_id: id)
      :ok = Jido.Shell.ShellSession.stop(id)
      {:ok, _} = Host.start_session(b, session_id: id)
      {:ok, b_pid} = Jido.Shell.ShellSession.lookup(id)
      assert {:ok, _} = Host.run(a, "write /only-a yes")
      assert {:ok, "yes"} = Host.read(a, "/only-a")
      assert {:error, _} = Host.read(b, "/only-a")
      :ok = Host.close(a)
      assert Process.alive?(b_pid)
    after
      Host.close(a)
      Host.close(b)
    end
  end
end
