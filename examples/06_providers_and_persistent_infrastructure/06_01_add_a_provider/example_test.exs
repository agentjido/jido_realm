Code.require_file("../../05_lifecycle/support.exs", __DIR__)
Code.require_file("report_provider.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.CustomProviderTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Entry, Error, Execution}
  alias Jido.Realm.Host.Examples.ReportProvider
  import Jido.Realm.Host.Examples.LifecycleSupport, only: [await: 3, configure: 1]

  @wait 4_000
  @secret "internal fixture credential"
  @report "quarterly report\n"

  setup %{tmp_dir: root} do
    configure(Path.join(root, "snapshots"))
    registry = start_supervised!({ReportProvider, []})
    options = %{registry: registry, notify: self()}

    profile = %{
      provider: {ReportProvider, Map.put(options, :credential, @secret)},
      policy: :full_access,
      require: %{isolation: :mediated, network: :disabled, cancellation: :cooperative},
      tools: ["copy", "wait", "missing-result"],
      store: "reports"
    }

    profiles = Application.fetch_env!(:jido_realm, :profiles)

    Application.put_env(
      :jido_realm,
      :profiles,
      Map.merge(profiles, %{
        report: profile,
        read_only: %{profile | policy: [:read, :execute, :import]},
        wrong_access: %{
          profile
          | policy: [:read, :execute],
            provider: {ReportProvider, Map.put(options, :report_access, :read_write)}
        },
        stronger: %{profile | require: %{isolation: :container}},
        broken: %{
          profile
          | provider: {ReportProvider, Map.put(options, :raise_after_allocate, @secret)}
        },
        slow: %{
          profile
          | provider: {ReportProvider, Map.put(options, :hold_before_allocate, true)}
        },
        delayed_release: %{
          profile
          | provider: {ReportProvider, Map.put(options, :fail_release_once, true)}
        },
        invalid: %{profile | provider: {Enum, []}}
      })
    )

    %{registry: registry}
  end

  test "the public API uses the provider tree for files, literal argv, and snapshots",
       %{registry: registry} do
    assert {:ok, workspace} = Host.open(profile: :report)
    assert_receive {:provisioned, %{id: lease_id, controller: controller}}, @wait
    refute inspect(:sys.get_status(controller)) =~ @secret

    snapshot =
      try do
        assert {:ok,
                %{
                  capabilities: %{
                    provider: ReportProvider,
                    isolation: :mediated,
                    network: :disabled,
                    cancellation: :cooperative,
                    tree_access: :read_write
                  }
                }} = Host.info(workspace)

        assert :ok = Host.mkdir(workspace, "build")

        assert :ok =
                 Host.write_stream(workspace, "build/draft; Q4", ["quarterly ", "report\n"])

        assert {:ok, "quarterly"} = Host.read_chunk(workspace, "build/draft; Q4", 0, 9)

        assert {:ok, %Execution{exit_status: 0, output: "cop", truncated: true}} =
                 Host.run(workspace, ["copy", "draft; Q4", "report.txt"],
                   cwd: "build",
                   output_limit: 3
                 )

        assert {:ok, @report, revision} =
                 Host.read(workspace, "build/report.txt", revision: true)

        assert :ok =
                 Host.write(workspace, "build/report.txt", "reviewed\n", expected: revision)

        assert {:error, %Error{code: :stale_revision}} =
                 Host.write(workspace, "build/report.txt", "stale edit", expected: revision)

        assert {:ok, [%Entry{path: "build/report.txt"}]} =
                 Host.find(workspace, "build", contains: "reviewed")

        assert {:ok, %Execution{exit_status: 1}} =
                 Host.run(workspace, ["copy", "../outside", "bad"], cwd: "build")

        assert {:error, %Error{code: :policy_denied}} = Host.run(workspace, ["anything"])
        assert {:ok, snapshot} = Host.save(workspace)
        snapshot
      after
        assert :ok = Host.close(workspace)
      end

    assert_receive {:release_result, ^lease_id, :ok}, @wait
    assert ReportProvider.active_leases(registry) == []

    assert {:ok, reopened} = Host.open(profile: :read_only, from: snapshot)
    assert_receive {:provisioned, %{id: new_lease_id}}, @wait
    assert new_lease_id != lease_id

    try do
      assert {:ok, "reviewed\n"} = Host.read(reopened, "build/report.txt")
      assert {:ok, %{capabilities: %{tree_access: :read_only}}} = Host.info(reopened)

      assert {:ok, %Execution{exit_status: 1}} =
               Host.run(reopened, ["copy", "report.txt", "intrusion"], cwd: "build")

      assert {:error, %Error{code: :policy_denied}} =
               Host.write(reopened, "build/report.txt", "intrusion")

      assert {:ok, "reviewed\n"} = Host.read(reopened, "build/report.txt")
    after
      assert :ok = Host.close(reopened)
    end

    assert {:ok, memory} = Host.open(profile: :memory, from: snapshot)

    try do
      assert {:ok, "reviewed\n"} = Host.read(memory, "build/report.txt")
    after
      assert :ok = Host.close(memory)
    end
  end

  test "capability rejection releases the allocated lease and refuses the handle",
       %{registry: registry} do
    for {profile, capability} <- [stronger: :isolation, wrong_access: :tree_access] do
      assert {:error, %Error{code: :unsupported_capability, details: %{capability: ^capability}}} =
               Host.open(profile: profile)

      assert_receive {:provisioned, %{id: id}}, @wait
      assert_receive {:release_result, ^id, :ok}, @wait
      assert ReportProvider.active_leases(registry) == []
    end

    assert {:error, %Error{code: :invalid_profile}} = Host.open(profile: :invalid)
  end

  test "a callback crash after allocation releases by lease ID and hides its cause",
       %{registry: registry} do
    assert {:error, %Error{code: :provider_failed} = error} = Host.open(profile: :broken)
    refute inspect(error) =~ @secret
    assert_receive {:provisioned, %{id: id}}, @wait
    assert_receive {:release_result, ^id, :ok}, @wait
    assert ReportProvider.active_leases(registry) == []
  end

  test "release can revoke the lease before a delayed provision returns",
       %{registry: registry} do
    opener = Task.async(fn -> Host.open(profile: :slow, timeout_ms: 500) end)
    assert_receive {:provision_waiting, %{id: id, controller: controller}}, @wait

    assert {:error, %Error{code: :open_timeout}} = Task.await(opener, @wait)
    assert_receive {:release_result, ^id, :ok}, @wait
    send(controller, {:resume_provision, id})
    assert_receive {:allocation_refused, ^id}, @wait
    assert ReportProvider.active_leases(registry) == []
  end

  test "the cleanup owner revokes a pending lease when the opener exits", %{registry: registry} do
    owner = self()

    {opener, monitor} =
      spawn_monitor(fn ->
        Host.open(profile: :slow, owner: owner, timeout_ms: 10_000)
      end)

    assert_receive {:provision_waiting, %{id: id, controller: controller}}, @wait
    Process.exit(opener, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^opener, :killed}, @wait
    assert_receive {:release_result, ^id, :ok}, @wait
    send(controller, {:resume_provision, id})
    assert_receive {:allocation_refused, ^id}, @wait
    assert ReportProvider.active_leases(registry) == []
  end

  test "the cleanup owner releases after the workspace controller dies", %{registry: registry} do
    assert {:ok, workspace} = Host.open(profile: :report)
    assert_receive {:provisioned, %{id: id, controller: controller}}, @wait
    monitor = Process.monitor(controller)
    Process.exit(controller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^controller, :killed}, @wait
    assert_receive {:release_result, ^id, :ok}, @wait
    assert ReportProvider.active_leases(registry) == []
    assert {:error, %Error{code: :closed}} = Host.read(workspace, "report.txt")
    assert await(fn -> Host.close(workspace) == :ok end, "Release was not confirmed", @wait)
  end

  test "a release failure stays explicit until the provider confirms a retry",
       %{registry: registry} do
    assert {:ok, workspace} = Host.open(profile: :delayed_release)
    assert_receive {:provisioned, %{id: id}}, @wait
    assert {:error, %Error{code: :cleanup_unconfirmed}} = Host.close(workspace)
    assert_receive {:release_result, ^id, {:error, :cleanup_unconfirmed}}, @wait
    assert {:error, %Error{code: :closed}} = Host.write(workspace, "late", "denied")
    assert :ok = Host.close(workspace)
    assert_receive {:release_result, ^id, :ok}, @wait
    assert :ok = Host.close(workspace)
    assert ReportProvider.active_leases(registry) == []
  end

  test "run streams output, confirms cancellation, and fences an unknown command result" do
    assert {:ok, workspace} = Host.open(profile: :report)

    try do
      run = Task.async(fn -> Host.run(workspace, ["wait"], timeout_ms: 10_000) end)

      id =
        await(
          fn ->
            with {:ok, %{active_execution_id: id}} when is_binary(id) <- Host.info(workspace),
                 {:ok, %{bytes: "waiting\n"}} <- Host.output(workspace, id) do
              id
            else
              _ -> nil
            end
          end,
          "The provider did not reach the command checkpoint",
          @wait
        )

      assert {:error, %Error{code: :busy}} = Host.save(workspace)
      assert :ok = Host.cancel(workspace, id)

      assert {:ok, %Execution{id: ^id, status: :cancelled, exit_status: nil}} =
               Task.await(run, @wait)

      assert :ok = Host.write(workspace, "report.txt", @report)
      assert {:ok, _} = Host.save(workspace)

      assert {:error, %Error{code: :quiescence_unknown}} =
               Host.run(workspace, ["missing-result"])

      assert {:ok, %{phase: :quiescence_unknown}} = Host.info(workspace)

      assert {:error, %Error{code: :quiescence_unknown}} =
               Host.write(workspace, "late", "denied")

      assert {:error, %Error{code: :quiescence_unknown}} = Host.save(workspace)
    after
      assert :ok = Host.close(workspace)
    end
  end
end
