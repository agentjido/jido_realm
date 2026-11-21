defmodule Jido.Realm.DockerLifecycleTest do
  use ExUnit.Case

  alias Jido.Realm.{Memory, Placement, Profile, Runner, Session}

  @tag :tmp_dir
  test "a lost Docker create reply blocks further work unless cleanup is confirmed", %{
    tmp_dir: dir
  } do
    docker = Path.join(dir, "docker")

    File.write!(docker, """
    #!/bin/sh
    context=$2
    shift 2
    case "$1 $2" in
      "image inspect") printf '%s linux no-volumes\n' 'sha256:#{String.duplicate("0", 64)}' ;;
      "container create")
        [ "$context" = "daemon-unreachable" ] && exit 1
        head -c 20000 /dev/zero ;;
      "container rm") [ "$context" = "remove-confirmed" ] ;;
      *) exit 1 ;;
    esac
    """)

    File.chmod!(docker, 0o700)
    path = System.fetch_env!("PATH")
    System.put_env("PATH", dir <> ":" <> path)
    on_exit(fn -> System.put_env("PATH", path) end)

    memory = start_supervised!(Memory)
    assert :ok = Memory.run(memory, :create, "test.sh", "exit 0")
    assert {:ok, profile} = Profile.resolve(:program)

    for {context, result} <- [
          {"remove-confirmed", :runtime_launch_failed},
          {"remove-unknown", :unknown},
          {"daemon-unreachable", :unknown}
        ] do
      runner = {Runner.Docker, image: "cached", context: context, workspace: :memory}

      session =
        start_supervised!(
          {Session,
           profile: profile,
           provider: {Placement, {:borrow, {Memory, memory}}},
           runners: %{bash: runner}},
          id: make_ref()
        )

      assert {:ok, %{capabilities: capabilities}} = Session.open(session)
      assert :bash in capabilities
      assert {:ok, %{id: id} = request} = Runner.request(:bash, "test.sh", [])

      case result do
        :runtime_launch_failed ->
          assert {:error, :runtime_launch_failed} = Session.run(session, profile, request, :all)

          assert {:ok, %{content: "exit 0"}} =
                   Session.file(session, profile, :read, "test.sh", nil)

        :unknown ->
          assert {:error, {:unknown, ^id}} = Session.run(session, profile, request, :all)
          assert {:error, :session_closed} = Session.file(session, profile, :read, "test.sh", nil)
      end
    end
  end
end
