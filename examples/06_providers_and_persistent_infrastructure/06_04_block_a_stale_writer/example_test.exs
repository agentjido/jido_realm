Code.require_file("../06_03_recover_an_old_command/support.exs", __DIR__)

defmodule Jido.Realm.Host.Examples.BlockStaleWriterTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  import Jido.Realm.Host.Examples.RecoverySupport

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Error, Execution}
  alias Jido.Realm.Host.Examples.{MachinePool, RecoveryHost, RecoveryProvider}

  defmodule RevokedProvider do
    @behaviour Jido.Realm.Host.Provider

    @impl true
    def provision(lease, %{options: target}, nil) do
      {:ok, target, %{tree_access: :read_write}, lease.infrastructure}
    end

    @impl true
    def run(target, _) do
      send(target, :tried_run)
      {:error, :lease_revoked}
    end

    @impl true
    def file(target, _), do: send(target, :tried_file)

    @impl true
    def capture(target, _), do: send(target, :tried_capture)

    @impl true
    def release(_, _), do: :ok
  end

  setup do
    preserve_configuration()
  end

  test "a provider-confirmed revocation fences the controller" do
    Application.put_env(:jido_realm, :profiles, %{
      writer: %{
        provider: {RevokedProvider, self()},
        infrastructure: MachinePool.provider(),
        policy: [:read, :write, :execute, :save],
        store: "results"
      }
    })

    machine = reference("provider-resource", "command-1").infrastructure
    assert {:ok, ws} = Host.open(profile: :writer, infrastructure: machine)

    try do
      assert {:error, %Error{code: :lease_revoked}} = Host.run(ws, ["write-report"])
      assert_received :tried_run
      assert {:ok, %{phase: :lease_revoked}} = Host.info(ws)
      assert {:error, %Error{code: :lease_revoked}} = Host.write(ws, "result", "blocked")
      assert {:error, %Error{code: :lease_revoked}} = Host.save(ws)
      refute_received :tried_file
      refute_received :tried_capture
    after
      assert :ok = Host.close(ws)
    end
  end

  @tag :tmp_dir
  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to run the local recovery fixture"
  end

  test "revoking a lease and confirming its writers stopped are separate checks", %{tmp_dir: root} do
    %{host: host, machine: machine, tree: tree} = fixture(root)
    ref = new_reference(machine, "old-writer")
    old = peer()

    assert :ok =
             eval(
               old,
               """
               {:ok, owner} = Agent.start(fn -> nil end, name: :old_workspace)
               {:ok, workspace} = Jido.Realm.Host.open(profile: :run, infrastructure: machine, owner: owner)
               Agent.update(owner, fn _ -> workspace end)
               """,
               machine: machine
             )

    assert {:ok, old_id} = RecoveryHost.current_writer(host, machine)
    old_environment = {RecoveryHost.options(host), %{id: old_id, infrastructure: machine}}

    run =
      Task.async(fn ->
        eval(
          old,
          """
          workspace = Agent.get(:old_workspace, & &1)
          Jido.Realm.Host.run(workspace, ["write-report"], command: command)
          """,
          command: ref
        )
      end)

    assert :ok = await_start(tree, ref)

    assert {:error, :quiescence_unknown} =
             RecoveryProvider.capture(old_environment, %{entries: 20, bytes: 1024})

    assert {:error, :cleanup_unconfirmed} = RecoveryHost.revoke_writer(host, machine, old_id)
    assert {:ok, %{status: :running}} = Host.recover_command(:recovery, ref, :inspect)
    assert_writer_busy(machine)

    folder = RecoveryHost.job_path(tree, ref)
    assert :ok = File.touch(Path.join(folder, "finish"))
    assert {:ok, %Execution{exit_status: 0}} = Task.await(run, 15_000)
    assert File.read!(Path.join(folder, "report")) == "complete\n"
    assert_writer_busy(machine)

    assert :ok = RecoveryHost.revoke_writer(host, machine, old_id)
    assert {:ok, replacement} = Host.open(profile: :run, infrastructure: machine)

    try do
      assert {:ok, new_id} = RecoveryHost.current_writer(host, machine)
      assert new_id != old_id
      assert :ok = Host.write(replacement, "new.txt", "replacement\n")

      assert {:ok, %{phase: :ready}} =
               eval(old, "Jido.Realm.Host.info(Agent.get(:old_workspace, & &1))")

      assert {:error, %Error{code: :lease_revoked}} =
               eval(old, "Jido.Realm.Host.save(Agent.get(:old_workspace, & &1))")

      assert {:error, %Error{code: :lease_revoked}} =
               eval(
                 old,
                 ~s|Jido.Realm.Host.write(Agent.get(:old_workspace, & &1), "new.txt", "stale")|
               )

      assert {:ok, %{phase: :lease_revoked}} =
               eval(old, "Jido.Realm.Host.info(Agent.get(:old_workspace, & &1))")

      # These requests stand for work already sent to the provider by the old lease.
      delayed = new_reference(machine, "late-launch")

      assert {:error, :lease_revoked} =
               RecoveryProvider.file(old_environment, {:write, "new.txt", "stale", :any})

      assert {:error, :lease_revoked} =
               RecoveryProvider.run(old_environment, %{
                 argv: ["write-report"],
                 cwd: ".",
                 command: delayed
               })

      assert {:error, %Error{code: :command_not_found}} =
               Host.recover_command(:recovery, delayed, :inspect)

      assert :ok = eval(old, "Jido.Realm.Host.close(Agent.get(:old_workspace, & &1))")
      assert :ok = RecoveryHost.revoke_writer(host, machine, old_id)
      assert {:ok, ^new_id} = RecoveryHost.current_writer(host, machine)

      assert {:ok, snapshot} = Host.save(replacement)
      assert {:ok, restored} = Host.open(profile: :memory, from: snapshot)

      try do
        assert {:ok, "replacement\n"} = Host.read(restored, "new.txt")
        old_report = Path.relative_to(Path.join(folder, "report"), tree)
        assert {:ok, "complete\n"} = Host.read(restored, old_report)
      after
        assert :ok = Host.close(restored)
      end
    after
      assert :ok = Host.close(replacement)
    end
  end

  @tag :tmp_dir
  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to run the local recovery fixture"
  end

  test "transport loss grants no new writer and preserves the recovery reference", %{
    tmp_dir: root
  } do
    %{host: host, machine: machine, tree: tree} = fixture(root)
    ref = new_reference(machine, "unreachable-writer")
    assert {:ok, previous} = Host.open(profile: :lost_reply, infrastructure: machine)
    assert {:ok, previous_id} = RecoveryHost.current_writer(host, machine)

    assert {:error, %Error{code: :quiescence_unknown}} =
             Host.run(previous, ["write-report"], command: ref)

    assert :ok = await_start(tree, ref)
    assert :ok = RecoveryHost.set_transport(host, :offline)

    try do
      for action <- [:inspect, :stop] do
        assert {:error, %Error{code: :quiescence_unknown}} =
                 Host.recover_command(:recovery, ref, action, timeout_ms: 2_000)
      end

      assert {:error, %Error{code: :cleanup_unconfirmed}} =
               Host.open(profile: :run, infrastructure: machine, timeout_ms: 2_000)

      assert {:error, %Error{code: :quiescence_unknown}} =
               Host.write(previous, "result.txt", "blocked")

      assert {:error, %Error{code: :quiescence_unknown}} = Host.save(previous)
      assert {:ok, ^previous_id} = RecoveryHost.current_writer(host, machine)
    after
      assert :ok = RecoveryHost.set_transport(host, :online)
    end

    assert {:ok, %{status: :running}} = Host.recover_command(:recovery, ref, :inspect)
    assert_writer_busy(machine)
    assert {:ok, %{status: :exited}} = Host.recover_command(:recovery, ref, :stop)
    assert_writer_busy(machine)
    assert :ok = RecoveryHost.revoke_writer(host, machine, previous_id)
    assert :ok = Host.close(previous)
    assert {:ok, replacement} = Host.open(profile: :run, infrastructure: machine)
    assert :ok = Host.close(replacement)
  end

  defp eval(peer, script, bindings \\ []) do
    {result, _bindings} = :peer.call(peer, Code, :eval_string, [script, bindings], 15_000)
    result
  end

  defp assert_writer_busy(machine) do
    assert {:error, %Error{code: :infrastructure_busy}} =
             Host.open(profile: :run, infrastructure: machine)
  end
end
