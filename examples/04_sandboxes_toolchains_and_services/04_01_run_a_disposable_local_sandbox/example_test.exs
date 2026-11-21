Code.require_file("../../05_lifecycle/support.exs", __DIR__)
Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.DisposableSandboxTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Error, Execution, Sandbox}
  alias Jido.Realm.Host.Examples.DisposableSandbox
  import Jido.Realm.Host.Examples.LifecycleSupport

  @report "Checked report\n"

  setup %{tmp_dir: root} do
    configure(Path.join(root, "snapshots"))
    missing = Path.expand(Path.join(root, "missing-tool"))

    put_profile(:local, %{
      provider: :local,
      policy: :full_access,
      tools: ["/bin/cat", "/bin/cp", "/bin/sleep", missing],
      require: %{isolation: :process},
      store: "reports"
    })

    %{missing: missing}
  end

  test "Local runs an approved executable, saves its file, and removes the owned root" do
    exercise_disposable(:local, :process)
  end

  test "a missing native executable returns a start failure and the tree stays available", %{
    missing: missing
  } do
    assert {:ok, workspace} = Host.open(profile: :local)

    try do
      assert {:error, %Error{operation: :run, code: :policy_denied}} =
               Host.run(workspace, ["/bin/sh"])

      assert {:error, %Error{operation: :run, code: :start_failed}} =
               Host.run(workspace, [missing])

      assert {:ok, %{capabilities: %{stdin: :pipe}}} = Host.info(workspace)

      assert {:ok, %Execution{status: :exited, exit_status: 0}} =
               Host.run(workspace, ["/bin/sleep", "0"], stdin: :pipe)

      assert {:ok, %Execution{status: :exited, exit_status: 0, output: ""}} =
               Host.run(workspace, ["/bin/cat"], stdin: :closed, timeout_ms: 1_000)

      assert {:ok, %{phase: :ready}} = Host.info(workspace)
      assert {:ok, _} = DisposableSandbox.copy_report(workspace, @report)
    after
      assert :ok = Host.close(workspace)
    end
  end

  test "Local admission refuses an unsafe profile and unmet isolation" do
    profile = Application.fetch_env!(:jido_realm, :profiles).local

    for changes <- [
          %{policy: [:read, :execute]},
          %{tools: []},
          %{tools: ["cp"]},
          %{checkout: "relative/checkout"},
          %{image: "alpine:3.20"}
        ] do
      put_profile(:invalid, Map.merge(profile, changes))
      assert {:error, %Error{code: :invalid_profile}} = Host.open(profile: :invalid)
    end

    put_profile(:isolated, %{profile | require: %{isolation: :container}})

    assert {:error, %Error{code: :unsupported_capability, details: %{capability: :isolation}}} =
             Host.open(profile: :isolated)

    put_profile(:offline, %{profile | require: %{network: :disabled}})

    assert {:error, %Error{code: :unsupported_capability, details: %{capability: :network}}} =
             Host.open(profile: :offline)
  end

  test "closing a Local workspace preserves a host-owned checkout", %{tmp_dir: root} do
    checkout = Path.join(root, "checkout")
    File.mkdir!(checkout)
    profile = Application.fetch_env!(:jido_realm, :profiles).local
    put_profile(:checkout, Map.put(profile, :checkout, checkout))

    assert {:ok, workspace} = Host.open(profile: :checkout)
    assert :ok = Host.write(workspace, "kept.txt", @report)
    assert :ok = Host.close(workspace)
    assert File.read!(Path.join(checkout, "kept.txt")) == @report
  end

  test "a timeout waits for the direct Local process to exit" do
    assert {:ok, workspace} = Host.open(profile: :local)
    {_controller, sandbox} = provider(workspace, :native)

    try do
      assert %{cancellation: :direct_child} = Sandbox.capabilities(sandbox)

      task =
        Task.async(fn ->
          Host.run(workspace, ["/bin/sleep", "30"], timeout_ms: 2_000)
        end)

      %{os_pid: pid} = running_process(sandbox)

      assert {"", 0} = probe_pid(pid)
      assert {:error, %Error{code: :busy}} = Host.save(workspace)

      assert {:ok, %Execution{status: :timed_out, exit_status: nil}} =
               Task.await(task, 5_000)

      assert {_, status} = probe_pid(pid)
      assert status != 0
      assert {:ok, _} = DisposableSandbox.copy_report(workspace, @report)
    after
      assert :ok = Host.close(workspace)
    end

    refute File.exists?(sandbox.root)
  end

  test "losing the Local command port leaves a live process and fences the tree" do
    assert {:ok, workspace} = Host.open(profile: :local)
    {_controller, sandbox} = provider(workspace, :native)
    task = Task.async(fn -> Host.run(workspace, ["/bin/sleep", "30"]) end)
    %{handle: port, os_pid: pid} = running_process(sandbox)

    try do
      assert {"", 0} = probe_pid(pid)
      assert true == Port.close(port)

      assert {:error, %Error{code: :quiescence_unknown}} = Task.await(task)
      assert {"", 0} = probe_pid(pid)
      assert {:error, %Error{code: :quiescence_unknown}} = Host.save(workspace)

      assert {:error, %Error{code: :quiescence_unknown}} =
               Host.write(workspace, "late.txt", "Blocked")

      assert {:error, %Error{code: :cleanup_unconfirmed}} = Host.close(workspace)
      assert File.dir?(sandbox.root)
    after
      System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)

      await(
        fn -> match?({_, code} when code != 0, probe_pid(pid)) end,
        "The test fixture process did not exit"
      )

      DynamicSupervisor.terminate_child(Sandbox.Supervisor, sandbox.pid)
      File.rm_rf!(sandbox.root)
    end
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to compare native cleanup on Docker"
  end

  test "Docker runs the same report and removes the container and owned root" do
    exercise_disposable(:docker, :container)
  end

  defp exercise_disposable(profile, isolation) do
    assert {:ok, workspace} = Host.open(profile: profile)
    {_controller, sandbox} = provider(workspace, :native)
    closed = Process.monitor(sandbox.pid)
    if profile == :docker, do: clean_up_docker_on_failure(sandbox)

    snapshot =
      try do
        assert {:ok, %{capabilities: %{provider: ^profile, isolation: ^isolation}}} =
                 Host.info(workspace)

        assert {:ok, snapshot} = DisposableSandbox.copy_report(workspace, @report)
        assert :ok = Host.write(workspace, "report.txt", "Unsaved change")
        assert File.dir?(sandbox.root)
        if profile == :docker, do: assert([_] = containers(sandbox))
        snapshot
      after
        assert :ok = Host.close(workspace)
      end

    assert_receive {:DOWN, ^closed, :process, _, :normal}
    refute File.exists?(sandbox.root)
    assert {:error, :not_found} = Sandbox.attach(sandbox.id)
    assert {:error, %Error{code: :closed}} = Host.read(workspace, "report.txt")
    assert :ok = Host.close(workspace)
    if profile == :docker, do: assert([] = containers(sandbox))

    assert {:ok, restored} = Host.open(profile: :memory, from: snapshot)

    try do
      assert {:ok, @report} = Host.read(restored, "report.txt")
    after
      assert :ok = Host.close(restored)
    end
  end

  defp probe_pid(pid),
    do: System.cmd("/bin/kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true)

  defp running_process(sandbox) do
    await(
      fn ->
        {:ok, %{services: services}} = Sandbox.info(sandbox)

        Enum.find_value(services, fn
          {_, %{status: :running, os_pid: pid} = service} when is_integer(pid) -> service
          _ -> nil
        end)
      end,
      "The local foreground process did not start"
    )
  end

  defp put_profile(name, profile) do
    profiles = Application.fetch_env!(:jido_realm, :profiles)
    Application.put_env(:jido_realm, :profiles, Map.put(profiles, name, profile))
  end
end
