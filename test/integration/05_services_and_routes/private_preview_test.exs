defmodule Jido.Realm.Integration.PrivatePreviewTest do
  use ExUnit.Case

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.{Preview, Runner}

  @moduletag :docker
  @page "<!doctype html><h1>Realm preview</h1>\n"
  @app """
  import http.server
  import os
  http.server.ThreadingHTTPServer(('0.0.0.0', int(os.environ['PORT'])),
                                  http.server.SimpleHTTPRequestHandler).serve_forever()
  """

  defmodule Job do
    use Jido.Action,
      name: "preview_realm_app",
      schema:
        Jido.Joi.object(%{
          job: Jido.Joi.atom(),
          id: Jido.Joi.string() |> Jido.Joi.optional(),
          ttl: Jido.Joi.integer() |> Jido.Joi.optional()
        })

    alias Jido.Realm

    @impl true
    def run(job, context) do
      case perform(job, context) do
        {:ok, data} ->
          reply(context, data)

        :ok ->
          reply(context, %{})

        {:error, reason} ->
          {:error, Jido.Error.execution_error("Preview job failed", details: %{reason: reason})}
      end
    end

    defp perform(%{job: :start}, context), do: start(context)

    defp perform(%{job: :copy_and_start}, context) do
      with {:ok, _} <- Realm.copy(context, {:source, "page.html"}, {:work, "index.html"}),
           do: start(context)
    end

    defp perform(%{job: :stop, id: id}, context), do: Realm.stop_preview(context, :work, id)

    defp perform(%{job: :share, id: id, ttl: ttl}, context),
      do: Realm.share_preview(context, :work, id, ttl)

    defp perform(%{job: :unshare, id: id}, context), do: Realm.unshare_preview(context, :work, id)

    defp start(context) do
      Realm.start_preview(context, :work, :python, "app.py",
        inputs: ["index.html"],
        timeout_ms: 1_500
      )
    end

    defp reply(context, result) do
      {:ok, signal} = Jido.Agent.build_signal(context, "realm.preview.result", result)
      {:ok, context.agent_state, [Jido.Agent.Directive.reply(signal)]}
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "realm_preview_integration", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:source, profile: :files)
      realm(:work, profile: :program)
    end

    routes do
      signal_source("/test/realm/preview")
      route("realm.job", AgentJobs.Job)
      route("preview.job", Job)
    end
  end

  setup context do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listener)
    base = "http://127.0.0.1:#{port}/preview"
    tls = if context[:https], do: tls_listener()
    image = System.get_env("JIDO_REALM_PYTHON_IMAGE", "python:3.13-alpine")
    docker_context = System.get_env("JIDO_REALM_DOCKER_CONTEXT")

    adapter =
      {Runner.Docker,
       runtime: :python, runner: [image: image, context: docker_context], network: "bridge"}

    grants = Map.get(context, :grants, :all)

    work =
      {BindingFixture,
       kind: :local,
       preview: adapter,
       preview_base_url: base,
       preview_public_base_url: tls && tls.base,
       preview_max_public_ms: 4_000,
       preview_viewers: [:reviewer],
       grants: grants,
       files: %{"app.py" => @app}}

    source =
      {BindingFixture,
       kind: :local, files: %{"page.html" => @page}, grants: [:open, :read, :close]}

    %{agent: agent, bindings: bindings, placements: placements} =
      Scenarios.prepare(context, Agent, [work: work, source: source], :docker)

    session = bindings.work[:session]
    start_supervised!({Task, fn -> serve(:private, listener, session) end})

    if tls,
      do:
        start_supervised!({Task, fn -> serve(:public, tls.listener, session) end},
          id: :tls_gateway
        )

    assert :preview in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
    AgentJobs.succeeded(agent, :open, %{realm: :source})

    %{
      agent: agent,
      session: session,
      base: base,
      tls: tls,
      placements: placements,
      docker_context: docker_context
    }
  end

  test "05.01 returns a ready private route and removes the container on stop", ctx do
    write_page(ctx.agent)
    %{id: id, url: url} = started(ctx.agent, :start)
    assert {:ok, target} = Preview.target(ctx.session, id, :reviewer)
    assert target.host == "127.0.0.1"
    assert {200, @page} = request(url, :reviewer)
    assert {404, _} = request(url, :stranger)
    assert preview_call(ctx.agent, :start) |> reason() == :preview_in_progress

    assert {:ok, %{status: :committed}} = preview_call(ctx.agent, :stop, %{id: id})
    assert_removed(ctx, id, url, target.port)
  end

  test "05.02 startup failure returns diagnostics, cleans up, and permits a corrected start",
       ctx do
    write_page(ctx.agent)

    Files.assert_reply(ctx.agent, :edit, "app.py", %{
      realm: :work,
      content: "raise SystemExit('missing app configuration')"
    })

    assert {:service_start_failed, %{id: failed, output: output}} =
             preview_call(ctx.agent, :start) |> reason()

    assert output =~ "missing app configuration"
    assert {404, _} = request(ctx.base <> "/#{failed}/", :reviewer)
    assert_no_container(ctx, failed)

    Files.assert_reply(ctx.agent, :edit, "app.py", %{realm: :work, content: @app})
    %{id: id, url: url} = started(ctx.agent, :start)
    assert {200, @page} = request(url, :reviewer)
    {:ok, target} = Preview.target(ctx.session, id, :reviewer)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
    assert_removed(ctx, id, url, target.port)
  end

  test "05.02 an alive service that is never ready has no route or container", ctx do
    write_page(ctx.agent)

    app = """
    import http.server
    import os
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(503)
            self.end_headers()
    http.server.HTTPServer(('0.0.0.0', int(os.environ['PORT'])), Handler).serve_forever()
    """

    Files.assert_reply(ctx.agent, :edit, "app.py", %{realm: :work, content: app})

    assert {:service_start_failed, %{id: id, reason: :readiness_timeout}} =
             preview_call(ctx.agent, :start) |> reason()

    assert {404, _} = request(ctx.base <> "/#{id}/", :reviewer)
    assert_no_container(ctx, id)
  end

  @tag :https
  test "05.03 serves an anonymous HTTPS route, revokes it, and expires a second route", ctx do
    write_page(ctx.agent)
    %{id: id, url: private_url} = started(ctx.agent, :start)

    assert :invalid_preview_ttl =
             preview_call(ctx.agent, :share, %{id: id, ttl: 4_001}) |> reason()

    %{id: slug, url: public_url} = shared(ctx.agent, id, 4_000)
    assert {404, _} = request(private_url)
    assert {200, @page} = request(private_url, :reviewer)
    assert {404, _} = request(ctx.base <> "/#{slug}/")
    assert {404, _} = https_request(ctx.tls, ctx.tls.base <> "/#{id}/")
    assert {200, @page} = https_request(ctx.tls, public_url)

    assert {:ok, %{status: :committed}} = preview_call(ctx.agent, :unshare, %{id: id})
    assert {404, _} = https_request(ctx.tls, public_url)
    assert {200, @page} = request(private_url, :reviewer)

    ttl = 1_000
    %{url: expiring_url} = shared(ctx.agent, id, ttl)
    assert {200, @page} = https_request(ctx.tls, expiring_url)
    Process.sleep(ttl)
    assert {404, _} = https_request(ctx.tls, expiring_url)
    assert {200, @page} = request(private_url, :reviewer)

    %{url: closing_url} = shared(ctx.agent, id, 4_000)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
    assert {404, _} = https_request(ctx.tls, closing_url)
    assert {404, _} = request(private_url, :reviewer)
  end

  @tag :https
  @tag grants: [:open, :read, :write, :run, :preview, :close]
  test "05.03 a private preview grant gives no permission to publish", ctx do
    write_page(ctx.agent)
    %{id: id, url: url} = started(ctx.agent, :start)

    assert :permission_denied = preview_call(ctx.agent, :share, %{id: id, ttl: 1_000}) |> reason()
    assert {404, _} = https_request(ctx.tls, ctx.tls.base <> "/#{id}/")
    assert {200, @page} = request(url, :reviewer)
    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
  end

  test "08.01 copies from a read-only Realm, serves exact bytes, and previews a revision",
       ctx do
    %{id: id, url: url} = started(ctx.agent, :copy_and_start)
    assert {200, @page} = request(url, :reviewer)
    assert {404, _} = request(url, :stranger)
    assert ctx.placements.source.observe.("page.html") == {:ok, @page}
    assert ctx.placements.work.observe.("index.html") == {:ok, @page}
    {:ok, target} = Preview.target(ctx.session, id, :reviewer)

    assert {:ok, %{status: :committed}} = preview_call(ctx.agent, :stop, %{id: id})
    assert_removed(ctx, id, url, target.port)

    revised = String.replace(@page, "Realm preview", "Reviewed Realm preview")
    Files.assert_reply(ctx.agent, :edit, "index.html", %{realm: :work, content: revised})
    %{id: next_id, url: next_url} = started(ctx.agent, :start)
    assert next_id != id
    assert {200, ^revised} = request(next_url, :reviewer)
    assert {404, _} = request(next_url, :stranger)
    assert {404, _} = request(url, :reviewer)
    assert {:ok, @page} = ctx.placements.source.observe.("page.html")
    {:ok, next_target} = Preview.target(ctx.session, next_id, :reviewer)

    AgentJobs.succeeded(ctx.agent, :close, %{realm: :work})
    assert_removed(ctx, next_id, next_url, next_target.port)
  end

  @tag grants: [:open, :read, :run, :preview, :close]
  test "08.01 a denied copy starts no service", ctx do
    assert :permission_denied = preview_call(ctx.agent, :copy_and_start) |> reason()
    assert ctx.placements.work.observe.("index.html") == {:error, :not_found}
  end

  defp write_page(agent),
    do: Files.assert_reply(agent, :create, "index.html", %{realm: :work, content: @page})

  defp started(agent, job) do
    assert {:ok, %{status: :committed, reply: %{data: preview}}} = preview_call(agent, job)
    preview
  end

  defp preview_call(agent, job, data \\ %{}) do
    signal = Jido.Signal.new!("preview.job", Map.put(data, :job, job), source: "/test")
    Jido.AgentServer.call(agent, signal, timeout: 20_000)
  end

  defp reason({:ok, %{status: :failed, reply: nil, error: %{details: %{reason: reason}}}}),
    do: reason

  defp assert_removed(ctx, id, url, port) do
    assert {404, _} = request(url, :reviewer)
    assert {:error, :econnrefused} = :gen_tcp.connect({127, 0, 0, 1}, port, [], 500)
    assert_no_container(ctx, id)
  end

  defp assert_no_container(ctx, id) do
    prefix = if ctx.docker_context, do: ["--context", ctx.docker_context], else: []
    filter = "name=^/jido-realm-preview-#{id}$"

    assert {"", 0} =
             System.cmd("docker", prefix ++ ["container", "ls", "-aq", "--filter", filter])
  end

  defp request(url, viewer \\ nil) do
    headers = if viewer, do: [{~c"x-test-viewer", Atom.to_charlist(viewer)}], else: []

    assert {:ok, {{_, status, _}, _, bytes}} =
             :httpc.request(
               :get,
               {String.to_charlist(url), headers},
               [timeout: 2_000, autoredirect: false],
               body_format: :binary
             )

    {status, bytes}
  end

  defp shared(agent, id, ttl) do
    assert {:ok, %{status: :committed, reply: %{data: route}}} =
             preview_call(agent, :share, %{id: id, ttl: ttl})

    route
  end

  defp tls_listener do
    Application.ensure_all_started(:ssl)
    root = Path.join(System.tmp_dir!(), "realm-tls-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    cert = Path.join(root, "cert.pem")
    key = Path.join(root, "key.pem")

    assert {_, 0} =
             System.cmd(
               "openssl",
               ~w(req -x509 -newkey rsa:2048 -nodes -subj /CN=localhost -days 1) ++
                 ["-keyout", key, "-out", cert],
               stderr_to_stdout: true
             )

    assert {:ok, listener} =
             :ssl.listen(0, [
               :binary,
               active: false,
               packet: :http_bin,
               ip: {127, 0, 0, 1},
               certfile: String.to_charlist(cert),
               keyfile: String.to_charlist(key)
             ])

    assert {:ok, {{127, 0, 0, 1}, port}} = :ssl.sockname(listener)
    %{listener: listener, cert: cert, base: "https://localhost:#{port}/preview"}
  end

  defp https_request(tls, url) do
    assert {result, 0} =
             System.cmd("curl", [
               "--silent",
               "--show-error",
               "--noproxy",
               "*",
               "--max-time",
               "3",
               "--cacert",
               tls.cert,
               "--write-out",
               "\n%{http_code}",
               url
             ])

    {bytes, <<"\n", status::binary>>} = String.split_at(result, -4)
    {String.to_integer(status), bytes}
  end

  defp serve(:private, listener, session) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        respond(:private, :gen_tcp, socket, session)
        :gen_tcp.close(socket)
        serve(:private, listener, session)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(:public, listener, session) do
    case :ssl.transport_accept(listener) do
      {:ok, socket} ->
        case :ssl.handshake(socket, 1_000) do
          {:ok, socket} -> respond(:public, :ssl, socket, session)
          {:error, _} -> :ok
        end

        :ssl.close(socket)
        serve(:public, listener, session)

      {:error, :closed} ->
        :ok
    end
  end

  defp respond(access, transport, socket, session) do
    {status, bytes} =
      with {:ok, {:http_request, :GET, {:abs_path, "/preview/" <> route}, _}} <-
             transport.recv(socket, 0, 1_000),
           [id, ""] <- String.split(route, "/"),
           {:ok, viewer} <- read_viewer(transport, socket, :stranger),
           {:ok, target} <- route_target(access, session, id, viewer) do
        request("http://#{target.host}:#{target.port}/")
      else
        _ -> {404, ""}
      end

    transport.send(socket, [
      "HTTP/1.1 ",
      Integer.to_string(status),
      " Response\r\nConnection: close\r\nContent-Length: ",
      Integer.to_string(byte_size(bytes)),
      "\r\n\r\n",
      bytes
    ])
  end

  defp route_target(:private, session, id, viewer), do: Preview.target(session, id, viewer)
  defp route_target(:public, session, id, _viewer), do: Preview.public_target(session, id)

  defp read_viewer(transport, socket, viewer) do
    case transport.recv(socket, 0, 1_000) do
      {:ok, {:http_header, _, "X-Test-Viewer", _, "reviewer"}} ->
        read_viewer(transport, socket, :reviewer)

      {:ok, {:http_header, _, _, _, _}} ->
        read_viewer(transport, socket, viewer)

      {:ok, :http_eoh} ->
        {:ok, viewer}

      _ ->
        :error
    end
  end
end
