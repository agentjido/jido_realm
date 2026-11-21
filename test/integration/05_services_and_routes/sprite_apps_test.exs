Code.require_file("sprite_app_fixture.exs", __DIR__)

defmodule Jido.Realm.Integration.SpriteAppsTest do
  use ExUnit.Case

  alias Jido.Realm
  alias Jido.Realm.Conformance.{ServiceFixtures, SpriteAppFixture}
  alias Jido.Realm.{Placement, Plugin, Preview, Profile, Session}

  @moduletag :live_sprite
  @moduletag :tmp_dir
  @moduletag timeout: 420_000

  @setup """
  export MIX_ENV=test MIX_DEPS_PATH=/home/sprite/realm-phoenix-prep/deps
  export ERL_FLAGS='+S 2:2 +SDio 1 +SDcpu 1'
  export MIX_BUILD_PATH="$PWD/.build"
  cp -a /home/sprite/realm-phoenix-prep/build/. "$MIX_BUILD_PATH" || exit 78
  """

  test "a checked Phoenix service runs on a disposable Sprite", %{tmp_dir: dir} do
    options = %{
      runtime: :bash,
      port: 8080,
      check: {:check, :bash, @setup <> "\nmix test"},
      service: {:shell, :bash, @setup <> "\nexec mix run --no-halt"},
      service_file: "lib/realm_demo/page.ex",
      comment: "\n# Realm source changed\n",
      body: "<h1>Hello, world!</h1>"
    }

    run_case(dir, "phoenix", ServiceFixtures.phoenix(), options)
  end

  test "a checked TypeScript service runs on a disposable Sprite", %{tmp_dir: dir} do
    options = %{
      runtime: :javascript,
      port: 4173,
      check: {:check, :javascript, "verify.ts"},
      service: {:entrypoint, :javascript, "server.ts"},
      service_file: "server.ts",
      comment: "\n// Realm source changed\n",
      body: "<h1>Hello, Realm!</h1>"
    }

    run_case(dir, "ts", ServiceFixtures.typescript(), options)
  end

  defp run_case(dir, app, files, options) do
    token = System.get_env("SPRITES_TEST_TOKEN")

    assert is_binary(token) and byte_size(token) > 0,
           "Set SPRITES_TEST_TOKEN before running the live Sprite suite."

    cli = System.find_executable("sprite")
    assert cli, "Set up the Sprites CLI for the test organization to forward ports."
    client = Sprites.new(token)

    name =
      "jido-realm-pressure-#{app}-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    assert sprite_absent?(client, name), "The test Sprite name must be unused."
    on_exit(fn -> cleanup(client, name) end)

    sprite =
      case Sprites.create(client, name) do
        {:ok, sprite} -> sprite
        {:error, {:api_error, status, _}} -> flunk("SDK create returned HTTP #{status}.")
        {:error, _} -> flunk("SDK create did not return a confirmed Sprite.")
      end

    IO.puts("Sprite fixture allocated: #{name}")

    try do
      if options.runtime == :bash, do: prepare_phoenix(sprite, files)

      root = Path.join(dir, "source")
      {:ok, profile} = Profile.resolve(:program)

      adapter =
        {SpriteAppFixture,
         sprite: sprite, cli: cli, files: Map.keys(files), runtime: options.runtime}

      session =
        start_supervised!(
          {Session,
           profile: profile,
           owner: self(),
           provider: {Placement, {:local, root}},
           runners: %{options.runtime => adapter},
           preview: adapter,
           preview_base_url: "http://127.0.0.1/realm-gateway",
           preview_viewers: [:reviewer],
           max_run_ms: 30_000,
           commands: %{
             verify: %{grant: :run, schema: Jido.Joi.object(%{}), exec: options.check}
           },
           services: %{
             app: %{
               exec: options.service,
               ports: %{http: options.port},
               require_check: :verify
             }
           }}
        )

      context = context(session, profile, :all)
      assert {:ok, %{capabilities: capabilities}} = Realm.open(context, :work)
      assert [options.runtime, :commands, :services, :ports] -- capabilities == []

      try do
        seed(files, context)
        verify_service(context, session, profile, sprite, files, options)
      after
        assert :ok = Realm.close(context, :work)
        refute File.exists?(root)
      end
    after
      cleanup(client, name)
    end
  end

  defp verify_service(context, session, profile, sprite, files, options) do
    assert {:error, :unchecked_source} = Realm.start_service(context, :work, :app)
    spec = {:command, :verify, %{}}
    assert {:ok, check} = Realm.exec(context, :work, spec, request_id: "initial-check")
    assert check.status == :succeeded, check.output
    assert {:ok, ^check} = Realm.run_status(context, :work, check.id)
    assert {:ok, ^check} = Realm.exec(context, :work, spec, request_id: "initial-check")

    path = options.service_file

    assert {:ok, _} =
             Realm.file(context, :work, :edit, path, Map.fetch!(files, path) <> options.comment)

    assert {:error, :stale_source} =
             Realm.start_service(context, :work, :app, verified_by: check.id)

    assert {:ok, updated} = Realm.exec(context, :work, spec, request_id: "updated-check")
    assert updated.status == :succeeded, updated.output
    assert updated.source_ref != check.source_ref

    assert {:ok, %{id: service, ports: [:http]} = started} =
             Realm.start_service(context, :work, :app, verified_by: updated.id)

    refute Map.has_key?(started, :url)
    assert {:error, :not_found} = Preview.target(session, service, :reviewer)
    denied = context(session, profile, [:read, :run, :service])
    assert {:error, :permission_denied} = Realm.expose_port(denied, :work, service, :http)
    assert {:ok, %{id: endpoint}} = Realm.expose_port(context, :work, service, :http)
    assert {:error, :not_found} = Preview.target(session, endpoint, :stranger)
    assert {:ok, target} = Preview.target(session, endpoint, :reviewer)
    assert_app(target, options.body)
    assert {:ok, identity} = SpriteAppFixture.process_identity(sprite, options.port)

    assert :ok = Realm.close_port(context, :work, endpoint)
    assert {:error, :not_found} = Preview.target(session, endpoint, :reviewer)
    assert {:ok, ^identity} = SpriteAppFixture.process_identity(sprite, options.port)
    assert {:ok, %{id: replacement}} = Realm.expose_port(context, :work, service, :http)
    refute endpoint == replacement
    assert {:ok, ^target} = Preview.target(session, replacement, :reviewer)
    assert_app(target, options.body)

    assert :ok = Realm.stop_service(context, :work, service)
    assert {:error, :not_found} = Preview.target(session, replacement, :reviewer)
    assert {:error, _} = :gen_tcp.connect({127, 0, 0, 1}, target.port, [], 1_000)
    IO.puts("Sprite served port #{options.port}. Endpoint close preserved process #{identity}.")
  end

  defp seed(files, context) do
    paths =
      Enum.flat_map(Map.keys(files), fn file ->
        [_ | parts] = file |> Path.split() |> Enum.reverse()
        Enum.reverse(parts) |> Enum.scan(&Path.join(&2, &1))
      end)

    for path <- paths |> Enum.uniq() |> Enum.sort_by(&length(Path.split(&1))) do
      assert {:ok, _} = Realm.file(context, :work, :mkdir, path)
    end

    for {path, bytes} <- files do
      assert {:ok, _} = Realm.file(context, :work, :create, path, bytes)
    end
  end

  defp prepare_phoenix(sprite, files) do
    setup = "/home/sprite/realm-phoenix-prep"
    fs = Sprites.filesystem(sprite, "/home/sprite")

    for file <- ["mix.exs", "mix.lock"] do
      assert :ok =
               Sprites.Filesystem.write(
                 fs,
                 "realm-phoenix-prep/" <> file,
                 Map.fetch!(files, file)
               )
    end

    shell = """
    set -eu
    export MIX_ENV=test MIX_BUILD_PATH="$PWD/build"
    export ERL_FLAGS='+S 2:2 +SDio 1 +SDcpu 1'
    mix local.hex --force
    mix local.rebar --force
    mix deps.get --check-locked
    mix deps.compile
    """

    {out, code} =
      Sprites.cmd(sprite, "timeout", ["160s", "bash", "-lc", shell],
        dir: setup,
        timeout: 175_000,
        stderr_to_stdout: true
      )

    assert code == 0, out
  end

  defp assert_app(%{host: host, port: port}, body) do
    assert {:ok, %{status: 200, body: rendered}} =
             Req.get("http://#{host}:#{port}/",
               retry: false,
               receive_timeout: 6_000,
               decode_body: false
             )

    assert rendered =~ body
  end

  defp context(session, profile, grants) do
    %{
      plugin_inputs: %{
        Plugin => %{
          runtime: %{
            bindings: %{"work" => %{target: {:session, session, profile}, grants: grants}}
          }
        }
      }
    }
  end

  defp cleanup(client, name) do
    unless sprite_absent?(client, name) do
      assert :ok == Sprites.destroy(Sprites.sprite(client, name)), "SDK could not delete #{name}."
      assert sprite_absent?(client, name), "SDK could not confirm deletion of #{name}."
      IO.puts("Sprite deletion confirmed: #{name}")
    end
  end

  defp sprite_absent?(client, name),
    do: match?({:error, {:not_found, _}}, Sprites.get_sprite(client, name))
end
