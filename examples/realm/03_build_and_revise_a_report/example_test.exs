defmodule Jido.Realm.LuaShowcaseTest do
  use ExUnit.Case, parameterize: [%{storage: :local}, %{storage: :memory}]

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.Runner.Lua

  @moduletag :realm_example
  @moduletag :realm_lua_showcase

  @tag :tmp_dir
  test "an agent runs Lua setup, revises its program, and preserves the last report", context do
    outside = Path.join(context.tmp_dir, "outside.txt")
    File.write!(outside, "host only")

    fixtures = [work: {BindingFixture, kind: context.storage, runners: %{lua: {Lua, []}}}]

    %{agent: agent, observe: %{work: observe}} =
      Scenarios.prepare(context, AgentJobs.Programmer, fixtures, context.storage)

    AgentJobs.succeeded(agent, :open, %{realm: :work})

    Files.assert_reply(agent, :create, "setup.lua", %{
      realm: :work,
      content: ~S|assert(realm.write("prepared.txt", "prepared by Realm setup"))|
    })

    Files.assert_reply(agent, :create, "probe-path.txt", %{realm: :work, content: outside})

    Files.assert_reply(agent, :create, "app.lua", %{
      realm: :work,
      content: ~S'''
      local outside = realm.read("probe-path.txt")
      assert(not pcall(loadfile, outside))
      assert(not pcall(realm.read, outside))
      assert(not pcall(realm.write, "../outside.txt", "changed"))
      assert(realm.write("report.txt", string.upper(realm.read("prepared.txt"))))
      '''
    })

    assert %{status: :succeeded, published: ["prepared.txt"]} =
             AgentJobs.run_result(agent, "lua", "setup.lua")

    assert %{status: :succeeded, published: ["report.txt"]} =
             AgentJobs.run_result(agent, "lua", "app.lua")

    assert observe.("report.txt") == {:ok, "PREPARED BY REALM SETUP"}
    assert File.read!(outside) == "host only"

    Files.assert_reply(agent, :edit, "app.lua", %{
      realm: :work,
      content: ~S'''
      realm.write("report.txt", "partial result")
      error("intentional program failure")
      '''
    })

    assert %{status: :failed, published: [], output: reason} =
             AgentJobs.run_result(agent, "lua", "app.lua")

    assert reason =~ "intentional program failure"
    assert observe.("report.txt") == {:ok, "PREPARED BY REALM SETUP"}

    Files.assert_reply(agent, :edit, "app.lua", %{
      realm: :work,
      content: ~S|assert(realm.write("report.txt", "Updated: " .. realm.read("prepared.txt")))|
    })

    assert %{status: :succeeded, published: ["report.txt"]} =
             AgentJobs.run_result(agent, "lua", "app.lua")

    assert observe.("report.txt") == {:ok, "Updated: prepared by Realm setup"}
    AgentJobs.succeeded(agent, :close, %{realm: :work})
  end
end
