defmodule Jido.Realm.Integration.RealmServiceTest do
  use ExUnit.Case

  alias Jido.Realm
  alias Jido.Realm.{Placement, Plugin, Preview, Profile, Runner, Session}

  @typescript Jido.Realm.Conformance.ServiceFixtures.typescript()

  @tag :tmp_dir
  @tag :docker
  @tag timeout: 180_000
  test("checks and exposes a TypeScript service in Docker", %{tmp_dir: dir},
    do: verify(dir, :docker)
  )

  @tag :tmp_dir
  @tag :apple_container
  @tag timeout: 180_000
  test("checks and exposes a TypeScript service in Apple Container", %{tmp_dir: dir},
    do: verify(dir, :apple_container)
  )

  defp verify(dir, engine) do
    root = Path.join(dir, "typescript")
    {:ok, profile} = Profile.resolve(:program)

    options = [
      runtime: :javascript,
      image: System.get_env("JIDO_REALM_TYPESCRIPT_IMAGE", "node:22-alpine"),
      files: Map.keys(@typescript),
      network: "jido-realm-coding-preview-local"
    ]

    adapter =
      case engine do
        :docker -> {Runner.Docker, staged: options}
        :apple_container -> {Runner.AppleContainer, options}
      end

    session =
      start_supervised!(
        {Session,
         profile: profile,
         owner: self(),
         provider: {Placement, {:local, root}},
         runners: %{javascript: adapter},
         preview: adapter,
         preview_base_url: "http://127.0.0.1/gateway",
         preview_viewers: [:reviewer],
         preview_public_base_url: "https://realm.example/public",
         preview_max_public_ms: 10_000,
         commands: %{
           verify: %{
             grant: :verify,
             schema: Jido.Joi.object(%{}),
             exec: {:check, :javascript, "verify.ts"},
             options: [timeout_ms: 15_000]
           }
         },
         services: %{
           site: %{
             exec: {:entrypoint, :javascript, "server.ts"},
             options: [timeout_ms: 15_000],
             ports: %{http: 4173},
             require_check: :verify
           }
         }}
      )

    context = context(session, profile, :all)
    no_check = context(session, profile, [:read, :run])
    no_route = context(session, profile, [:read, :run, :service])

    assert {:ok, %{capabilities: capabilities}} = Realm.open(context, :work)
    assert [:javascript, :commands, :services, :ports, :background] -- capabilities == []

    for {path, text} <- @typescript do
      assert {:ok, _} = Realm.file(context, :work, :create, path, text)
    end

    assert {:ok, [%{name: :verify}]} = Realm.commands(context, :work)
    assert {:ok, []} = Realm.commands(no_check, :work)
    assert {:error, :unchecked_source} = Realm.start_service(context, :work, :site)
    spec = {:command, :verify, %{}}
    id = "verify-typescript"

    assert {:ok, %{status: :succeeded, id: ^id, source_ref: source_ref} = check} =
             Realm.exec(context, :work, spec, request_id: id)

    assert check.output =~ "TypeScript check passed"
    assert {:ok, ^check} = Realm.exec(context, :work, spec, request_id: id)
    assert {:ok, ^check} = Realm.run_status(context, :work, id)
    assert {:error, :permission_denied} = Realm.exec(no_check, :work, spec, request_id: id)
    assert {:error, :permission_denied} = Realm.run_status(no_check, :work, id)

    assert {:error, :request_conflict} =
             Realm.exec(context, :work, spec, request_id: id, source_ref: source_ref)

    assert {:ok, _} =
             Realm.file(
               context,
               :work,
               :edit,
               "server.ts",
               @typescript["server.ts"] <> "// edit\n"
             )

    assert {:error, :stale_source} = Realm.start_service(context, :work, :site, verified_by: id)
    assert {:ok, %{status: :succeeded, id: check_id}} = Realm.exec(context, :work, spec)

    run = {:entrypoint, :javascript, "verify.ts"}

    assert {:ok, %{id: "background-ts"}} =
             Realm.exec(context, :work, run, mode: :background, request_id: "background-ts")

    assert %{status: :succeeded, output: output} = await_run(context, "background-ts", 100)
    assert output =~ "TypeScript check passed"

    assert {:error, :request_conflict} =
             Realm.exec(context, :work, run, request_id: "background-ts")

    assert {:ok, %{id: "background-ts"}} =
             Realm.exec(context, :work, run, mode: :background, request_id: "background-ts")

    assert {:ok, %{id: service, ports: [:http]} = started} =
             Realm.start_service(context, :work, :site, verified_by: check_id)

    refute Map.has_key?(started, :url)
    assert {:error, :not_found} = Preview.target(session, service, :reviewer)
    assert {:error, :permission_denied} = Realm.expose_port(no_route, :work, service, :http)
    assert {:error, :not_found} = Realm.expose_port(context, :work, service, :other)
    assert {:ok, %{id: private}} = Realm.expose_port(context, :work, service, :http)
    assert {:error, :not_found} = Preview.target(session, private, :stranger)
    assert {:ok, %{host: host, port: port} = target} = Preview.target(session, private, :reviewer)

    assert {:ok, %{status: 200, body: "<h1>Hello, Realm!</h1>"}} =
             Req.get("http://#{host}:#{port}/", retry: false)

    assert {:ok, %{id: public}} =
             Realm.expose_port(context, :work, service, :http, access: :public, ttl_ms: 10_000)

    assert {:ok, ^target} = Preview.public_target(session, public)
    assert :ok = Realm.close_port(context, :work, private)
    assert {:error, :not_found} = Preview.target(session, private, :reviewer)
    assert {:ok, ^target} = Preview.public_target(session, public)
    assert {:ok, %{id: replacement}} = Realm.expose_port(context, :work, service, :http)
    refute replacement == private
    assert {:ok, ^target} = Preview.target(session, replacement, :reviewer)
    assert :ok = Realm.stop_service(context, :work, service)
    assert {:error, :not_found} = Preview.target(session, replacement, :reviewer)
    assert {:error, :not_found} = Preview.public_target(session, public)
    assert {:error, _} = :gen_tcp.connect({127, 0, 0, 1}, port, [], 500)
    assert :ok = Realm.close(context, :work)
    refute File.exists?(root)
  end

  defp await_run(context, id, retries) do
    assert {:ok, status} = Realm.run_status(context, :work, id)

    if status.status == :running and retries > 0 do
      Process.sleep(100)
      await_run(context, id, retries - 1)
    else
      status
    end
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
end
