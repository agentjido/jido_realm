defmodule Jido.Realm.Integration.NodeReportTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{BindingFixture, Scenarios}
  alias Jido.Realm.Runner

  defmodule ReportProfile do
    @behaviour Jido.Realm.Profile

    @impl true
    def requirements do
      %Jido.Realm.Profile{
        required: [:files, :javascript],
        execution_controls: %{
          javascript: [:read_only_inputs, :private_scratch, :loopback_only, :non_root]
        }
      }
    end
  end

  defmodule RunReport do
    alias Jido.Agent.Directive
    alias Jido.{Joi, Realm}

    use Jido.Action,
      name: "run_node_report",
      schema: Joi.object(%{input: Joi.string(), outside: Joi.string()})

    @program ~S'''
    const assert = require('node:assert/strict');
    const fs = require('node:fs');
    const os = require('node:os');

    assert.notEqual(process.getuid(), 0);
    assert.deepEqual(Object.keys(os.networkInterfaces()), ['lo']);

    const input = fs.readFileSync('input.txt', 'utf8');
    assert.throws(() => fs.readFileSync('unlisted.txt'), { code: 'ENOENT' });
    assert.throws(() => fs.readFileSync(process.argv[2]), { code: 'ENOENT' });
    assert.throws(
      () => fs.writeFileSync('input.txt', 'changed'),
      { code: 'EROFS' }
    );

    const scratch = '/tmp/report.txt';
    fs.writeFileSync(scratch, 'report: ' + input, { flag: 'wx' });
    process.stdout.write(fs.readFileSync(scratch, 'utf8'));
    '''

    @impl true
    def run(%{input: input, outside: outside}, context) do
      with {:ok, _} <- Realm.open(context, :work),
           {:ok, _} <- Realm.file(context, :work, :create, "report.cjs", @program),
           {:ok, _} <- Realm.file(context, :work, :create, "input.txt", input),
           {:ok, _} <- Realm.file(context, :work, :create, "unlisted.txt", "outside the run"),
           {:ok, result} <-
             Realm.exec(context, :work, :javascript, "report.cjs",
               inputs: ["input.txt"],
               args: [outside],
               timeout_ms: 5_000
             ),
           :ok <- Realm.close(context, :work),
           {:ok, reply} <- Jido.Agent.build_signal(context, "realm.report.ran", result) do
        {:ok, context.agent_state, [Directive.reply(reply)]}
      else
        {:error, reason} ->
          {:error,
           Jido.Error.execution_error("Realm report job failed", details: %{reason: reason})}
      end
    end
  end

  defmodule ReportAgent do
    use Jido.Agent, name: "realm_node_report_agent", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:work, profile: ReportProfile)
    end

    routes do
      signal_source("/test/realm/node-report")
      route("realm.report.run", RunReport)
    end
  end

  defmodule UnqualifiedRunner do
    @behaviour Runner

    @impl true
    def prepare(:javascript, _lease, _options), do: {:ok, :prepared}

    @impl true
    def controls(_state), do: [:read_only_inputs]

    @impl true
    def execute(_state, _request, _grants), do: {:error, :unexpected_dispatch}
  end

  realm_case "04.01 require an execution binding even with a Local tree",
    agent: ReportAgent,
    cases: [files_only: [work: {BindingFixture, kind: :local}]] do
    %{agent: agent, observe: %{work: observe}} ->
      assert_refused(agent, observe)
  end

  realm_case "04.01 require controls from the selected runner",
    agent: ReportAgent,
    evidence: :controlled_provider,
    cases: [
      unqualified: [
        work:
          {BindingFixture,
           kind: :local,
           report: %{
             javascript: true,
             read_only_inputs: true,
             private_scratch: true,
             loopback_only: true,
             non_root: true
           },
           runners: %{javascript: {UnqualifiedRunner, []}}}
      ]
    ] do
    %{agent: agent, observe: %{work: observe}} ->
      assert_refused(agent, observe)
  end

  @tag :docker
  @tag :tmp_dir
  test "04.01 a Node program reads approved files and writes to private scratch", context do
    image = System.get_env("JIDO_REALM_JAVASCRIPT_IMAGE", "node:22-alpine")
    docker_context = System.get_env("JIDO_REALM_DOCKER_CONTEXT")
    runner = {Runner.Docker, image: image, context: docker_context}
    fixtures = [work: {BindingFixture, kind: :local, runners: %{javascript: runner}}]

    %{agent: agent, observe: %{work: observe}} =
      Scenarios.prepare(context, ReportAgent, fixtures, :docker_node)

    outside = Path.expand("host-only.txt", context.tmp_dir)
    File.write!(outside, "host only")
    input = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    expected = "report: " <> input

    assert {:ok,
            %{
              status: :committed,
              reply: %{
                type: "realm.report.ran",
                data: %{
                  id: id,
                  status: :succeeded,
                  exit_code: 0,
                  output: ^expected,
                  published: []
                }
              }
            }} = run_report(agent, input, outside)

    assert File.read!(outside) == "host only"
    assert observe.("input.txt") == {:ok, input}
    assert observe.("unlisted.txt") == {:ok, "outside the run"}
    assert observe.("report.txt") == {:error, :not_found}

    prefix = if docker_context, do: ["--context", docker_context], else: []
    filter = "name=^/jido-realm-" <> id <> "$"
    assert {"", 0} = System.cmd("docker", prefix ++ ["ps", "-aq", "--filter", filter])
  end

  defp assert_refused(agent, observe) do
    assert {:ok,
            %{
              status: :failed,
              error: %{details: %{reason: {:required_capability_unavailable, :javascript}}}
            }} = run_report(agent, "input", "/unused")

    assert observe.("report.cjs") == {:error, :not_found}
  end

  defp run_report(agent, input, outside) do
    signal =
      Jido.Signal.new!("realm.report.run", %{input: input, outside: outside}, source: "/test")

    Jido.AgentServer.call(agent, signal, timeout: 25_000)
  end
end
