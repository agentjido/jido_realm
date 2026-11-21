defmodule Jido.Realm.Integration.SpriteLifecycleTest do
  use ExUnit.Case

  alias Jido.Realm.Conformance.{AgentJobs, Files, Scenarios}
  alias Jido.Realm.Provider.Sprite
  alias Jido.Realm.Session

  @evidence_file "realm-evidence.txt"

  test "06.04 SDK requests preserve a borrowed Sprite and remove the allocated Sprite", context do
    requests = start_supervised!({Agent, fn -> %{} end})
    client = Sprites.new("test-only")

    req =
      client.req
      |> Req.merge(adapter: __MODULE__.Transport, retry: false)
      |> Req.Request.put_private(:sprite_requests, requests)

    client = %{client | req: req}

    borrowed_name = exercise(context, client)

    assert %{^borrowed_name => %{@evidence_file => "Realm Sprite test\n"}} =
             Agent.get(requests, & &1)
  end

  test "06.04 maps provider errors and keeps an unconfirmed deletion visible" do
    client = Sprites.new("test-only")

    reply = fn status, body ->
      fn req -> {req, Req.Response.new(status: status, body: body)} end
    end

    opts = fn mode, adapter ->
      req =
        client.req
        |> Req.merge(adapter: __MODULE__.Stub, retry: false)
        |> Req.Request.put_private(:sprite_reply, adapter)

      %{
        mode: mode,
        client: %{client | req: req},
        name: "fixture",
        root: "/home/sprite",
        readable: ["missing.txt", "large.txt"]
      }
    end

    for {mode, status, reason} <- [
          {:borrowed, 404, :not_found},
          {:borrowed, 503, :sprite_unavailable},
          {:owned, 409, :already_exists},
          {:owned, 403, :sprite_unavailable},
          {:owned, 503, :unknown}
        ] do
      assert {:error, ^reason} = Sprite.open(opts.(mode, reply.(status, %{})))
    end

    assert {:error, :invalid_sprite_binding} = Sprite.open(%{})

    assert {:error, :invalid_sprite_binding} =
             Sprite.open(%{opts.(:owned, reply.(200, %{})) | readable: ["../outside"]})

    adapter = fn req ->
      {status, body} =
        cond do
          req.method == :delete ->
            {503, %{}}

          String.ends_with?(req.url.path, "/list") ->
            {200,
             %{"entries" => [%{"name" => "large.txt", "isDir" => false, "size" => 1_048_577}]}}

          req.method == :post ->
            {201, %{}}
        end

      {req, Req.Response.new(status: status, body: body)}
    end

    assert {:ok, %{binding: {Sprite, handle}} = lease} = Sprite.open(opts.(:owned, adapter))
    assert {:error, :not_found} = Sprite.run(handle, :read, "missing.txt", nil)
    assert {:error, :backend_error} = Sprite.run(handle, :read, "large.txt", nil)
    assert {:error, :unsupported_file_operation} = Sprite.run(handle, :create, "large.txt", "new")
    assert {:error, :unknown} = Sprite.close(lease, [])
  end

  defmodule Stub do
    def run(req), do: Req.Request.get_private(req, :sprite_reply).(req)
  end

  @tag :live_sprite
  @tag timeout: 120_000
  test "06.04 repeats the allocation and attachment case on a real Sprite", context do
    client = Sprites.new(System.fetch_env!("SPRITES_TEST_TOKEN"))
    exercise(context, client)
  end

  defp exercise(context, client) do
    prefix = "jido-realm-test-" <> Base.encode16(:crypto.strong_rand_bytes(10), case: :lower)
    borrowed_name = prefix <> "-borrowed"
    owned_name = prefix <> "-owned"
    start_supervised!({Jido, name: context.module})

    opts = %{
      mode: :borrowed,
      client: client,
      name: borrowed_name,
      root: "/home/sprite",
      readable: [@evidence_file]
    }

    if context[:live_sprite] do
      on_exit(fn ->
        for name <- [borrowed_name, owned_name],
            match?({:ok, _}, Sprites.get_sprite(client, name)) do
          assert :ok = Sprites.destroy(Sprites.sprite(client, name))
        end
      end)
    end

    assert {:ok, sprite} = Sprites.create(client, borrowed_name)
    fs = Sprites.filesystem(sprite, opts.root)
    assert :ok = Sprites.Filesystem.write(fs, @evidence_file, "Realm Sprite test\n")

    borrower = start_agent(context, opts)
    assert %{capabilities: [:files]} = AgentJobs.succeeded(borrower, :open, %{realm: :work})

    assert {:error, {:not_found, _}} = Sprites.get_sprite(client, owned_name)
    owner = start_agent(context, %{opts | mode: :owned, name: owned_name})
    assert %{capabilities: [:files]} = AgentJobs.succeeded(owner, :open, %{realm: :work})
    assert {:ok, _} = Sprites.get_sprite(client, owned_name)

    Files.assert_reply(borrower, :read, @evidence_file, %{realm: :work}, %{
      content: "Realm Sprite test\n"
    })

    Files.assert_rejected(borrower, :read, "outside.txt", :permission_denied, %{realm: :work})

    Files.assert_rejected(borrower, :edit, @evidence_file, :permission_denied, %{
      realm: :work,
      content: "mutated"
    })

    AgentJobs.succeeded(borrower, :close, %{realm: :work})
    assert {:ok, "Realm Sprite test\n"} = Sprites.Filesystem.read(fs, @evidence_file)
    assert {:ok, _} = Sprites.get_sprite(client, borrowed_name)

    AgentJobs.succeeded(owner, :close, %{realm: :work})
    assert {:error, {:not_found, _}} = Sprites.get_sprite(client, owned_name)
    assert {:ok, _} = Sprites.get_sprite(client, borrowed_name)
    borrowed_name
  end

  defp start_agent(context, opts) do
    session = start_supervised!({Session, provider: {Sprite, opts}}, id: make_ref())

    Scenarios.start_agent(context.module, AgentJobs.Work, %{
      work: [session: session, grants: [:open, :read, :close]]
    })
  end

  defmodule Transport do
    def run(req) do
      requests = Req.Request.get_private(req, :sprite_requests)
      ["v1", "sprites" | resource] = String.split(req.url.path, "/", trim: true)

      {status, body} =
        Agent.get_and_update(requests, &respond(req, resource, &1))

      {req, Req.Response.new(status: status, body: body)}
    end

    defp respond(%{method: :post, body: body}, [], sprites) do
      name = Jason.decode!(IO.iodata_to_binary(body))["name"]

      if Map.has_key?(sprites, name),
        do: {{409, %{}}, sprites},
        else: {{201, %{"id" => name}}, Map.put(sprites, name, %{})}
    end

    defp respond(%{method: :delete}, [name], sprites),
      do: {{204, ""}, Map.delete(sprites, name)}

    defp respond(req, [name | path], sprites) do
      case Map.fetch(sprites, name) do
        {:ok, files} ->
          {result, files} = file_request(req, path, files)
          {result, Map.put(sprites, name, files)}

        :error ->
          {{404, %{}}, sprites}
      end
    end

    defp file_request(%{method: :get}, [], files), do: {{200, %{}}, files}

    defp file_request(%{method: :get}, ["fs", "list"], files) do
      entries =
        for {name, bytes} <- files,
            do: %{"name" => name, "isDir" => false, "size" => byte_size(bytes)}

      {{200, %{"entries" => entries}}, files}
    end

    defp file_request(%{method: :get, url: url}, ["fs", "read"], files) do
      case Map.fetch(files, filename(url)) do
        {:ok, bytes} -> {{200, bytes}, files}
        :error -> {{404, %{}}, files}
      end
    end

    defp file_request(%{method: :put, url: url, body: body}, ["fs", "write"], files),
      do: {{200, ""}, Map.put(files, filename(url), IO.iodata_to_binary(body))}

    defp filename(url),
      do: url.query |> URI.decode_query() |> Map.fetch!("path") |> Path.basename()
  end
end
