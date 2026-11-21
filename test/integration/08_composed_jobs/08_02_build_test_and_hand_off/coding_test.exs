defmodule Jido.Realm.Integration.CodingTest do
  use ExUnit.Case, parameterize: [%{kind: :local}, %{kind: :memory}]

  alias Jido.Realm.{Artifacts, Runner, Tree}
  alias Jido.Realm.Conformance.{BindingFixture, Scenarios}

  @html "<h1>Order total: 42</h1>\n"

  defmodule Repair do
    use Jido.Action,
      name: "repair_order_total",
      schema: Jido.Joi.object(%{runtime: Jido.Joi.atom(), extension: Jido.Joi.string()})

    alias Jido.Realm

    @impl true
    def run(%{runtime: runtime, extension: extension}, context) do
      with {:ok, _} <- Realm.open(context, :work) do
        result = repair(context, runtime, extension)
        with :ok <- Realm.close(context, :work), do: reply(context, result)
      else
        {:error, _} = error -> reply(context, error)
      end
    end

    defp repair(context, runtime, extension) do
      source = "orders/totals." <> extension
      verify = "verify." <> extension
      opts = [cwd: "orders", inputs: ["totals." <> extension], timeout_ms: 5_000]

      with {:ok, %{content: original, revision: base}} <-
             Realm.file(context, :work, :read_revision, source),
           {:ok, %{status: :failed, output: diagnostic} = failed} <-
             Realm.exec(context, :work, runtime, verify, opts),
           {:ok, revised, diff} <- fix(diagnostic, original),
           {:ok, _} <- Realm.file(context, :work, :edit_revision, source, {base, revised}),
           {:ok, %{revision: revision}} <- Realm.file(context, :work, :read_revision, source),
           {:ok, %{status: :succeeded, truncated: false} = tested} <-
             Realm.exec(context, :work, runtime, verify, opts),
           {:ok, %{revision: ^revision}} <- Realm.file(context, :work, :read_revision, source),
           {:ok, _} <- Realm.file(context, :work, :create, "orders/report.html", tested.output),
           {:ok, artifact} <-
             Realm.publish_artifact(context, :work, "orders/report.html", ["orders/report.html"]) do
        {:ok,
         %{
           base: base,
           revision: revision,
           diff: diff,
           failed: failed,
           tested: tested,
           artifact: artifact
         }}
      else
        {:ok, %{status: :failed, output: diagnostic}} ->
          {:error, {:verification_failed, diagnostic}}

        {:ok, _} ->
          {:error, :unverified_change}

        {:error, _} = error ->
          error
      end
    end

    defp fix(diagnostic, original) do
      with true <- diagnostic =~ "incorrect order total",
           line when is_binary(line) <-
             Enum.find(String.split(original, "\n"), &String.contains?(&1, "quantity * unit + 1")) do
        updated = String.replace(line, "quantity * unit + 1", "quantity * unit")
        {:ok, String.replace(original, line, updated), "-#{line}\n+#{updated}\n"}
      else
        _ -> {:error, :unrecognized_failure}
      end
    end

    defp reply(context, {:ok, result}) do
      {:ok, signal} = Jido.Agent.build_signal(context, "realm.coding.result", result)
      {:ok, context.agent_state, [Jido.Agent.Directive.reply(signal)]}
    end

    defp reply(_context, {:error, reason}) do
      {:error,
       Jido.Error.execution_error("Coding job could not verify its change",
         details: %{reason: reason}
       )}
    end
  end

  defmodule CodingAgent do
    use Jido.Agent, name: "realm_coding_integration", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:work, profile: :program)
    end

    routes do
      signal_source("/test/realm/coding")
      route("coding.repair", Repair)
    end
  end

  test "08.02 an agent reproduces a failure, fixes the source, and hands off a tested report",
       context do
    run_verified_job(context, :lua)
  end

  @tag :docker
  test "08.02 runs the same repair and report handoff in the Docker toolchain", context do
    run_verified_job(context, :python)
  end

  test "08.02 a failed second run leaves the work available and makes no ready handoff",
       context do
    %{agent: agent, work: work, original: original, source: source} = prepare(context, :lua, 41)

    assert {:ok,
            %{
              status: :failed,
              reply: nil,
              error: %{details: %{reason: {:verification_failed, output}}}
            }} =
             repair(agent, :lua, "lua")

    assert output =~ "incorrect order total"
    assert work.observe.(source) == {:ok, String.replace(original, "unit + 1", "unit")}
    assert work.observe.("orders/report.html") == {:error, :not_found}
    assert_receive {:placement_released, :work, :borrowed}
  end

  defp run_verified_job(context, runtime) do
    %{
      agent: agent,
      work: work,
      store: store,
      original: original,
      source: source,
      extension: extension
    } =
      prepare(context, runtime, 42)

    assert {:ok, %{status: :committed, reply: %{type: "realm.coding.result", data: result}}} =
             repair(agent, runtime, extension)

    assert_receive {:placement_released, :work, :borrowed}
    assert result.failed.status == :failed
    assert result.failed.output =~ "incorrect order total"
    assert result.tested.status == :succeeded
    assert result.tested.exit_code == 0
    assert result.tested.runtime == runtime
    refute result.failed.id == result.tested.id
    assert result.base == Tree.revision(original)
    assert {:ok, revised} = work.observe.(source)
    assert revised == String.replace(original, "unit + 1", "unit")
    assert result.diff == expected_diff(runtime)
    assert result.revision == Tree.revision(revised)
    assert work.observe.("orders/report.html") == {:ok, @html}
    assert {:ok, %{content: @html}} = Artifacts.read(store, :reviewer, result.artifact.id)
  end

  defp expected_diff(:lua) do
    "-return function(quantity, unit) return quantity * unit + 1 end\n" <>
      "+return function(quantity, unit) return quantity * unit end\n"
  end

  defp expected_diff(:python),
    do: "-    return quantity * unit + 1\n+    return quantity * unit\n"

  defp repair(agent, runtime, extension) do
    signal =
      Jido.Signal.new!("coding.repair", %{runtime: runtime, extension: extension},
        source: "/test"
      )

    Jido.AgentServer.call(agent, signal, timeout: 20_000)
  end

  defp prepare(context, runtime, expected) do
    store = start_supervised!({Artifacts, viewers: [:reviewer]})
    {extension, original, verify, runner} = project(runtime, expected)
    source = "orders/totals." <> extension
    files = %{source => original, ("orders/verify." <> extension) => verify}

    binding =
      {BindingFixture,
       kind: context.kind,
       files: files,
       runners: %{runtime => runner},
       presenter: {Artifacts, store}}

    %{agent: agent, placements: %{work: work}} =
      Scenarios.prepare(context, CodingAgent, [work: binding], runtime)

    %{
      agent: agent,
      work: work,
      store: store,
      original: original,
      source: source,
      extension: extension
    }
  end

  defp project(:lua, expected) do
    original = "return function(quantity, unit) return quantity * unit + 1 end\n"

    verify = """
    local total = assert(load(realm.read("totals.lua")))()
    assert(total(6, 7) == #{expected}, "incorrect order total")
    print("<h1>Order total: " .. total(6, 7) .. "</h1>")
    """

    {"lua", original, verify, {Runner.Lua, []}}
  end

  defp project(:python, expected) do
    original = "def total(quantity, unit):\n    return quantity * unit + 1\n"

    verify = """
    from totals import total
    assert total(6, 7) == #{expected}, "incorrect order total"
    print(f"<h1>Order total: {total(6, 7)}</h1>")
    """

    image = System.get_env("JIDO_REALM_PYTHON_IMAGE", "python:3.13-alpine")
    runner = {Runner.Docker, image: image, context: System.get_env("JIDO_REALM_DOCKER_CONTEXT")}
    {"py", original, verify, runner}
  end
end
