defmodule Jido.Realm.Integration.NetworkAccessTest do
  use ExUnit.Case

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Scenarios}
  alias Jido.Realm.Runner

  @sink """
  from http.server import BaseHTTPRequestHandler, HTTPServer
  class Handler(BaseHTTPRequestHandler):
      def do_GET(self):
          print(self.path, flush=True)
          self.send_response(200)
          self.end_headers()
          self.wfile.write(b'approved endpoint')
      def log_message(self, *args):
          pass
  server = HTTPServer(('0.0.0.0', 8000), Handler)
  print('ready', flush=True)
  server.serve_forever()
  """

  @probe """
  import sys, urllib.request
  with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(sys.argv[1], timeout=1) as response:
      print(response.read().decode('ascii'))
  """

  @tag :docker
  test "04.02 only a binding with the approved private network reaches its peer", context do
    docker_context = System.get_env("JIDO_REALM_DOCKER_CONTEXT")
    prefix = if docker_context, do: ["--context", docker_context], else: []
    image = System.get_env("JIDO_REALM_PYTHON_IMAGE", "python:3.13-alpine")
    suffix = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    network = "jido-realm-net-#{suffix}"
    sink = "jido-realm-sink-#{suffix}"

    assert {_network_id, 0} = docker(prefix, ["network", "create", "--internal", network])

    on_exit(fn ->
      docker(prefix, ["container", "rm", "--force", sink])
      docker(prefix, ["network", "rm", network])
    end)

    assert {_, 0} =
             docker(prefix, [
               "run",
               "--detach",
               "--pull=never",
               "--name",
               sink,
               "--network",
               network,
               "--log-driver=local",
               "--log-opt=compress=false",
               "--entrypoint",
               "python3",
               image,
               "-u",
               "-c",
               @sink
             ])

    assert_ready(prefix, sink, System.monotonic_time(:millisecond) + 3_000)

    assert {address, 0} =
             docker(prefix, [
               "inspect",
               "--format",
               "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
               sink
             ])

    assert {:ok, _} = :inet.parse_ipv4_address(String.to_charlist(String.trim(address)))
    base = "http://#{String.trim(address)}:8000"

    start_supervised!({Jido, name: context.module})
    opts = [image: image, context: docker_context]
    restricted = start_agent(context, opts)
    permitted = start_agent(context, Keyword.put(opts, :private_network, network))

    assert %{status: :failed, output: diagnostic} =
             AgentJobs.run_result(restricted, :python, "probe.py", %{
               args: [base <> "/denied"],
               timeout_ms: 5_000
             })

    assert diagnostic =~ "urlopen error"
    assert {"ready\n", 0} = docker(prefix, ["logs", sink])

    assert %{status: :succeeded, output: "approved endpoint\n"} =
             AgentJobs.run_result(permitted, :python, "probe.py", %{
               args: [base <> "/allowed"],
               timeout_ms: 5_000
             })

    assert {"ready\n/allowed\n", 0} = docker(prefix, ["logs", sink])
    AgentJobs.succeeded(restricted, :close, %{realm: :work})
    AgentJobs.succeeded(permitted, :close, %{realm: :work})
  end

  defp start_agent(context, options) do
    fixture =
      BindingFixture.prepare(%{
        realm: :work,
        fixture_options: [kind: :local, runners: %{python: {Runner.Docker, options}}]
      })

    agent =
      Scenarios.start_agent(context.module, AgentJobs.Programmer, %{work: fixture.runtime_options})

    assert :python in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
    fixture.seed.("probe.py", @probe)
    agent
  end

  defp assert_ready(prefix, sink, deadline) do
    case docker(prefix, ["logs", sink]) do
      {"ready\n", 0} ->
        :ok

      {output, _} ->
        assert System.monotonic_time(:millisecond) < deadline, output
        Process.sleep(40)
        assert_ready(prefix, sink, deadline)
    end
  end

  defp docker(prefix, args), do: System.cmd("docker", prefix ++ args, stderr_to_stdout: true)
end
