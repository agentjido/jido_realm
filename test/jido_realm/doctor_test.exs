defmodule Jido.Realm.DoctorTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Jido.Realm.Doctor
  alias Mix.Tasks.JidoRealm.Doctor, as: DoctorTask

  test "reports the selected lane as JSON" do
    json = capture_io(fn -> DoctorTask.run(~w(--lane core --format json --strict)) end)

    assert %{
             "host" => %{"elixir" => _, "otp" => _},
             "lanes" => [%{"name" => "core", "status" => "ready", "checks" => checks}]
           } = JSON.decode!(json)

    assert Enum.map(checks, & &1["id"]) == ~w(jido jido_vfs jido_shell lua erlexec)
  end

  test "checks only the test credential and keeps its value out of the report" do
    set_env("SPRITES_TOKEN", "production-token")
    set_env("SPRITES_TEST_TOKEN", " ")

    text = capture_io(fn -> DoctorTask.run(~w(--lane live_sprite)) end)
    assert text =~ "live_sprite | attention"
    assert text =~ "Set SPRITES_TEST_TOKEN"
    refute text =~ "production-token"

    json =
      capture_io(fn ->
        assert_raise Mix.Error, "Realm preflight requires attention", fn ->
          DoctorTask.run(~w(--lane live_sprite --format json --strict))
        end
      end)

    assert %{"lanes" => [%{"status" => "attention"}]} = JSON.decode!(json)

    System.put_env("SPRITES_TEST_TOKEN", "test-token")
    json = capture_io(fn -> DoctorTask.run(~w(--lane live_sprite --format json --strict)) end)
    assert %{"lanes" => [%{"status" => "ready"}]} = JSON.decode!(json)
    assert json =~ "Authorization is unverified"
    refute json =~ "test-token"
  end

  @tag :tmp_dir
  test "checks the selected Docker context and cached images", %{tmp_dir: dir} do
    docker = Path.join(dir, "docker")

    File.write!(docker, """
    #!/bin/sh
    [ "$1" = "--context" ] && [ "$2" = "realm-test" ] || exit 1
    shift 2

    case "$1 $2" in
      'version --format') printf '25.4.7\n' ;;
      'image inspect')
        case "$6" in
          bash:5.2|my-python-image) printf 'linux no-volumes\n' ;;
          *) printf 'context diagnostics can contain a secret\n'; exit 1 ;;
        esac
        ;;
      *) exit 1 ;;
    esac
    """)

    File.chmod!(docker, 0o700)
    set_env("PATH", dir <> ":" <> System.get_env("PATH", ""))
    set_env("JIDO_REALM_DOCKER_CONTEXT", "realm-test")
    set_env("JIDO_REALM_BASH_IMAGE", "bash:5.2")
    set_env("JIDO_REALM_PYTHON_IMAGE", "my-python-image")
    set_env("JIDO_REALM_JAVASCRIPT_IMAGE", "missing-image")

    assert %{lanes: [%{status: :attention, checks: checks}]} = Doctor.report([:docker])

    assert Enum.map(checks, &{&1.id, &1.status}) == [
             docker_engine: :ok,
             bash_image: :ok,
             python_image: :ok,
             javascript_image: :missing
           ]

    refute JSON.encode!(checks) =~ "diagnostics can contain a secret"
  end

  test "rejects an unknown lane" do
    assert_raise Mix.Error, ~r/Select a lane/, fn -> DoctorTask.run(~w(--lane unknown)) end
  end

  @tag :tmp_dir
  test "reports missing local executables and distinguishes a stopped Docker engine",
       %{tmp_dir: dir} do
    set_env("PATH", dir)
    set_env("JIDO_REALM_CHROME", Path.join(dir, "chrome"))
    set_env("SPRITES_TOKEN", "")

    assert %{lanes: [native, browser, docker, sprites, model]} =
             Doctor.report([:native, :browser, :docker, :sprites, :lmstudio])

    assert native.status == :ready
    assert Enum.map(browser.checks, &{&1.id, &1.status}) == [node: :missing, chrome: :missing]
    assert [%{id: :docker_cli, status: :missing}] = docker.checks
    assert %{id: "SPRITES_TOKEN", status: :missing} = List.last(sprites.checks)
    assert [%{id: :lmstudio_listener}] = model.checks

    stub(dir, "docker", "exit 1")
    delete_env("JIDO_REALM_DOCKER_CONTEXT")

    assert %{lanes: [%{checks: [%{id: :docker_engine, status: :missing}]}]} =
             Doctor.report([:docker])
  end

  @tag :tmp_dir
  test "reports browser tools and checks Apple's container system and image separately",
       %{tmp_dir: dir} do
    set_env("PATH", dir)
    set_env("JIDO_REALM_CHROME", stub(dir, "chrome", "exit 0"))
    stub(dir, "node", "printf 'v22.1.0\\n'")

    assert %{host: host, lanes: [%{status: :ready, checks: checks}]} = Doctor.report([:browser])
    assert Enum.map(checks, & &1.id) == [:node, :chrome]

    assert %{lanes: [%{status: :attention, checks: [%{id: missing}]}]} =
             Doctor.report([:apple_container])

    if host.os == :darwin and String.starts_with?(host.architecture, ["aarch64-", "arm64-"]) do
      assert missing == :container_cli
      set_env("JIDO_REALM_APPLE_IMAGE", "cached-alpine")
      stub(dir, "container", ~S([ "$1 $2" = "system status" ] || [ "$3" = "cached-alpine" ]))
      assert %{lanes: [%{status: :ready}]} = Doctor.report([:apple_container])
      set_env("JIDO_REALM_APPLE_IMAGE", "missing-alpine")

      assert %{lanes: [%{checks: [_, %{id: :container_image, status: :missing}]}]} =
               Doctor.report([:apple_container])

      stub(dir, "container", "exit 1")

      assert %{lanes: [%{checks: [%{id: :container_system, status: :missing}]}]} =
               Doctor.report([:apple_container])
    else
      assert missing == :apple_silicon
    end
  end

  defp stub(dir, name, script) do
    file = Path.join(dir, name)
    File.write!(file, "#!/bin/sh\n" <> script <> "\n")
    File.chmod!(file, 0o700)
    file
  end

  defp delete_env(key) do
    set_env(key, "")
    System.delete_env(key)
  end

  defp set_env(key, value) do
    previous = System.get_env(key)
    System.put_env(key, value)

    on_exit(fn ->
      if previous, do: System.put_env(key, previous), else: System.delete_env(key)
    end)
  end
end
