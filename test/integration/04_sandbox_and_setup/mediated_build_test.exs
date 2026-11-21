defmodule Jido.Realm.Integration.MediatedBuildTest do
  use ExUnit.Case, parameterize: [%{kind: :local}, %{kind: :memory}]

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.Runner

  setup context do
    observer = self()

    hook = fn operation, path, _, run ->
      if operation == :read, do: send(observer, {:backend_read, path})
      run.()
    end

    binding = {BindingFixture, kind: context.kind, runners: %{lua: {Runner.Lua, []}}, hook: hook}

    %{agent: agent, placements: %{work: work}} =
      Scenarios.prepare(context, AgentJobs.Programmer, [work: binding], context.kind)

    AgentJobs.succeeded(agent, :open, %{realm: :work})
    %{agent: agent, work: work}
  end

  test "04.07 a nested build sees declared inputs and its drafts without opening unlisted inputs",
       ctx do
    script = """
    assert(not pcall(realm.read, 'private.txt'))
    local input = realm.read('approved.txt')
    assert(realm.write('result.txt', input .. ' built'))
    assert(realm.read('result.txt') == input .. ' built')
    """

    ctx.work.seed.("project/build.lua", script)
    ctx.work.seed.("project/approved.txt", "nested input")
    ctx.work.seed.("project/private.txt", "workspace secret")
    ctx.work.seed.("approved.txt", "different root input")

    assert %{status: :succeeded, published: ["project/result.txt"]} =
             AgentJobs.run_result(ctx.agent, :lua, "build.lua", %{
               cwd: "project",
               inputs: ["approved.txt"]
             })

    assert_receive {:backend_read, "project/build.lua"}
    assert_receive {:backend_read, "project/approved.txt"}
    refute_received {:backend_read, "project/private.txt"}
    refute_received {:backend_read, "approved.txt"}
    assert ctx.work.observe.("project/result.txt") == {:ok, "nested input built"}
    assert ctx.work.observe.("result.txt") == {:error, :not_found}
  end

  test "04.05 failed setup publishes no state and a later run can use successful setup", ctx do
    ctx.work.seed.("approved.txt", "configured")
    ctx.work.seed.("protected.txt", "outside the setup input list")

    setup = """
    assert(not pcall(realm.read, 'protected.txt'))
    assert(realm.write('ready.txt', realm.read('approved.txt')))
    """

    Files.assert_reply(ctx.agent, :create, "setup.lua", %{
      realm: :work,
      content: setup <> "error('setup incomplete')"
    })

    assert %{status: :failed, output: diagnostics, published: []} =
             AgentJobs.run_result(ctx.agent, :lua, "setup.lua", %{inputs: ["approved.txt"]})

    assert diagnostics =~ "setup incomplete"
    assert ctx.work.observe.("ready.txt") == {:error, :not_found}

    Files.assert_reply(ctx.agent, :edit, "setup.lua", %{realm: :work, content: setup})

    assert %{status: :succeeded, published: ["ready.txt"]} =
             AgentJobs.run_result(ctx.agent, :lua, "setup.lua", %{inputs: ["approved.txt"]})

    Files.assert_reply(ctx.agent, :create, "verify.lua", %{
      realm: :work,
      content: "assert(realm.read('ready.txt') == 'configured'); print('ready')"
    })

    assert %{status: :succeeded, output: "ready\n"} =
             AgentJobs.run_result(ctx.agent, :lua, "verify.lua", %{inputs: ["ready.txt"]})

    assert ctx.work.observe.("ready.txt") == {:ok, "configured"}
    assert ctx.work.observe.("protected.txt") == {:ok, "outside the setup input list"}
    refute_received {:backend_read, "protected.txt"}
  end

  test "04.04 exceeding the draft budget preserves the last good build", ctx do
    script = """
    assert(realm.write('report.html', '<h1>Draft</h1>'))
    for n = 1, 16 do
      assert(realm.write('generated-' .. n .. '.txt', 'intermediate'))
    end
    """

    ctx.work.seed.("build.lua", script)
    ctx.work.seed.("report.html", "<h1>Last good build</h1>")

    assert %{status: :failed, output: diagnostic, published: []} =
             AgentJobs.run_result(ctx.agent, :lua, "build.lua")

    assert diagnostic =~ "draft_limit"
    assert ctx.work.observe.("report.html") == {:ok, "<h1>Last good build</h1>"}
    for n <- 1..16, do: assert(ctx.work.observe.("generated-#{n}.txt") == {:error, :not_found})
  end
end
