defmodule Jido.Realm.Host.BackendFileViewTest do
  use ExUnit.Case, async: false
  alias Jido.Realm.Host

  defmodule Remote do
    @behaviour Jido.Shell.Backend
    def init(config), do: {:ok, config}
    def cwd(state), do: {:ok, "/remote", state}
    def cd(state, _), do: {:ok, state}
    def terminate(_), do: :ok
    def cancel(_, _), do: :ok

    def execute(state, _, [], _) do
      {:ok, pid} =
        Task.Supervisor.start_child(Jido.Shell.CommandTaskSupervisor, fn ->
          send(state.session_pid, {:command_event, {:output, "remote bytes"}})
          send(state.session_pid, {:command_finished, {:ok, :done}})
        end)

      {:ok, pid, state}
    end
  end

  test "custom execution does not use the local VFS revision" do
    {:ok, workspace} = Host.open()
    on_exit(fn -> Host.close(workspace) end)
    :ok = Host.write(workspace, "/input", "local bytes")
    {:ok, local} = Host.file_view(workspace)
    {:ok, _session} = Host.start_session(workspace, backend: {Remote, %{}})
    {:ok, remote} = Host.file_view(workspace)
    assert remote.kind == :backend
    assert remote.path == :unknown
    assert {Remote, pid} = remote.owner
    assert is_pid(pid)
    assert remote.revision == :unavailable

    assert {:error, %Jido.Realm.Host.Error{code: :stale_file_view}} =
             Host.run(workspace, "cat /input", files: local)

    assert {:error, %Jido.Realm.Host.Error{code: :unversioned_file_view}} =
             Host.run(workspace, "cat /input", files: remote)

    assert {:ok, %{files: ^remote, output: "remote bytes", after_files: ^remote}} =
             Host.run(workspace, "cat /input", files: :current)

    :ok = Host.stop_session(workspace)
    assert {:ok, ^local} = Host.file_view(workspace)
  end

  test "virtual execution checks its own mount table" do
    {:ok, workspace} = Host.open()
    on_exit(fn -> Host.close(workspace) end)
    {:ok, session} = Host.start_session(workspace)
    {:ok, local} = Host.file_view(workspace)
    {:ok, pid} = Jido.Shell.ShellSession.lookup(session)
    {:ok, session} = Jido.Shell.ShellSessionServer.get_state(pid)

    :ok =
      Jido.Shell.VFS.mount(session.workspace_id, "/extra", Jido.VFS.Adapter.InMemory,
        name: make_ref()
      )

    {:ok, actual} = Host.file_view(workspace)
    assert actual.revision == :unavailable

    assert {:error, %Jido.Realm.Host.Error{code: :stale_file_view}} =
             Host.run(workspace, "pwd", files: local)
  end
end
