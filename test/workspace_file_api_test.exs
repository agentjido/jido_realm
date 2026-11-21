defmodule Jido.Realm.Host.FileApiTest do
  use ExUnit.Case, async: false
  alias Jido.Realm.Host
  alias Jido.Realm.Host.Error

  test "file mutations keep one handle and return the new results" do
    {:ok, ws} = Host.open()
    on_exit(fn -> Host.close(ws) end)

    assert :ok = Host.write(ws, "/file", ["new", [32, "bytes"]])
    assert {:ok, "new bytes"} = Host.read(ws, "/file")
    assert {:ok, [%Jido.Realm.Host.Entry{path: "/file"}]} = Host.list(ws)

    assert {:error, %Error{code: :not_found, operation: :read, resource: id}} =
             Host.read(ws, "/absent")

    assert id == ws.id
    assert :ok = Host.close(ws)
    assert :ok = Host.close(ws)
  end

  test "invalid paths and bytes fail before changing files" do
    {:ok, ws} = Host.open()
    on_exit(fn -> Host.close(ws) end)
    assert :ok = Host.write(ws, "/keep", "safe")

    for path <- ["relative", "/../keep", "/bad\0path", <<255>>, nil] do
      assert {:error, %Error{code: :invalid_input, operation: :write}} =
               Host.write(ws, path, "bad")

      assert {:error, %Error{code: :invalid_input, operation: :read}} = Host.read(ws, path)
      assert {:error, %Error{code: :invalid_input, operation: :mkdir}} = Host.mkdir(ws, path)

      assert {:error, %Error{code: :invalid_input, operation: :delete}} =
               Host.delete(ws, path)
    end

    assert {:error, %Error{code: :invalid_input}} = Host.write(ws, "/keep", %{bad: "bytes"})
    assert {:ok, "safe"} = Host.read(ws, "/keep")
    assert {:error, %Error{code: :invalid_input, operation: :open}} = Host.open(:invalid)

    assert {:error, %Error{code: :invalid_input, operation: :open}} =
             Host.open(owner: :invalid)

    assert {:error, %Error{code: :invalid_input, operation: :open}} =
             Host.open(policy: :unknown)
  end

  test "closed handles cannot change a new workspace with the same ID" do
    {:ok, old} = Host.open(id: "file-api-reused")
    assert :ok = Host.close(old)
    {:ok, fresh} = Host.open(id: "file-api-reused")
    on_exit(fn -> Host.close(fresh) end)
    assert :ok = Host.write(fresh, "/keep", "safe")
    assert {:error, %Error{code: :closed}} = Host.write(old, "/keep", "bad")
    assert :ok = Host.close(old)
    assert {:ok, "safe"} = Host.read(fresh, "/keep")
  end

  test "owner exit closes a workspace" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, ws} = Host.open()
        send(parent, {:workspace, ws})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:workspace, ws}
    monitor = Process.monitor(ws.lifetime)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 2_000
    assert {:error, %Error{code: :closed, operation: :read}} = Host.read(ws, "/file")
    assert :ok = Host.close(ws)
  end

  test "a busy request does not complete another caller's command" do
    {:ok, ws} = Host.open()
    on_exit(fn -> Host.close(ws) end)
    {:ok, session} = Host.shell(ws)
    {:ok, :subscribed} = Jido.Shell.ShellSessionServer.subscribe(session, self())
    running = Task.async(fn -> Host.run(ws, "seq 20 5") end)
    assert_receive {:jido_shell_session, ^session, {:command_started, "seq 20 5"}}
    assert {:error, %Error{code: :busy, operation: :run}} = Host.run(ws, "echo other")
    assert {:ok, %{status: :exited, exit_status: 0, output: output}} = Task.await(running)
    assert output =~ "20"
    {:ok, :unsubscribed} = Jido.Shell.ShellSessionServer.unsubscribe(session, self())
  end

  test "replacement rejects revisions from another resource generation" do
    {:ok, old} = Host.open(id: "capture-reused")
    :ok = Host.write(old, "/input", "old")
    {:ok, saved, revision} = Host.capture(old)
    :ok = Host.close(old)
    {:ok, fresh} = Host.open(id: "capture-reused")
    on_exit(fn -> Host.close(fresh) end)
    :ok = Host.write(fresh, "/input", "fresh")

    assert {:error, %Error{code: :stale_revision}} =
             Host.replace(fresh, saved, expected: revision)

    assert {:error, %Error{code: :closed}} = Host.capture(old)
    assert {:error, %Error{code: :closed}} = Host.replace(old, saved, expected: revision)
    assert {:ok, "fresh"} = Host.read(fresh, "/input")
  end

  test "invalid command and replacement options do not stop the controller" do
    {:ok, ws} = Host.open()
    on_exit(fn -> Host.close(ws) end)
    {:ok, capture, revision} = Host.capture(ws)

    for opts <- [[], :invalid, [expected: revision, extra: true]] do
      assert {:error, %Error{code: :invalid_input}} = Host.replace(ws, capture, opts)
    end

    for opts <- [
          :invalid,
          [timeout: 10],
          [timeout_ms: -1],
          [output_limit: -1],
          [execution_context: []]
        ] do
      assert {:error, %Error{code: :invalid_input}} = Host.run(ws, "pwd", opts)
    end

    assert {:error, %Error{code: :invalid_input}} = Host.start_session(ws, :invalid)
    assert {:ok, %{session: :stopped}} = Host.info(ws)
  end
end
