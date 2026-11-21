defmodule Jido.Realm.Integration.ProgramTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files}
  alias Jido.Realm.Runner

  defp lua(kind, grants \\ :all) do
    {BindingFixture, kind: kind, grants: grants, runners: %{lua: {Runner.Lua, []}}}
  end

  defp docker(runtime, image_var, default_image) do
    image = System.get_env(image_var, default_image)
    context = System.get_env("JIDO_REALM_DOCKER_CONTEXT")
    runner = {Runner.Docker, image: image, context: context}
    {BindingFixture, kind: :local, runners: %{runtime => runner}}
  end

  realm_case "03.01 an agent writes, runs, diagnoses, and repairs a program",
    agent: AgentJobs.Programmer,
    cases: [
      lua_on_memory: [work: lua(:memory)],
      lua_on_local: [work: lua(:local)]
    ],
    opt_in: [
      docker: [
        bash: [work: docker(:bash, "JIDO_REALM_BASH_IMAGE", "bash:5.2")],
        python: [work: docker(:python, "JIDO_REALM_PYTHON_IMAGE", "python:3.13-alpine")],
        javascript: [work: docker(:javascript, "JIDO_REALM_JAVASCRIPT_IMAGE", "node:22-alpine")]
      ]
    ] do
    %{agent: agent, observe: %{work: observe}, variant: variant} ->
      runtime = if variant in [:lua_on_memory, :lua_on_local], do: :lua, else: variant
      assert runtime in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
      Files.assert_reply(agent, :mkdir, "project", %{realm: :work})

      {entry, main, helper, broken, fixed} = program(runtime)
      create(agent, entry, main)
      create(agent, helper, broken)
      create(agent, "data.txt", "7")
      create(agent, "report.txt", "last good report")

      literal = "\"quoted\" ; $(printf injected)"

      request = %{
        cwd: "project",
        inputs: [helper, "data.txt"],
        args: [literal],
        timeout_ms: 5_000
      }

      assert %{id: first, status: :failed, exit_code: code, output: output, published: []} =
               AgentJobs.run_result(agent, runtime, entry, request)

      assert code > 0
      assert output =~ "repair the helper"
      assert observe.("project/report.txt") == {:ok, "last good report"}

      Files.assert_reply(agent, :edit, "project/" <> helper, %{realm: :work, content: fixed})

      assert %{id: second, status: :succeeded, exit_code: 0, output: report, published: paths} =
               AgentJobs.run_result(agent, runtime, entry, request)

      assert first != second
      assert report == "total=7 | " <> literal <> "\n"

      case runtime do
        :lua ->
          assert paths == ["project/report.txt"]

        _ ->
          assert paths == []
          # Docker mounts inputs read-only. The agent can save the returned output.
          Files.assert_reply(agent, :edit, "project/report.txt", %{realm: :work, content: report})
      end

      Files.assert_reply(agent, :read, "project/report.txt", %{realm: :work}, %{content: report})
      assert observe.("project/report.txt") == {:ok, report}
      AgentJobs.succeeded(agent, :close, %{realm: :work})
  end

  realm_case "03.01 apply run, read, and write grants before program effects",
    agent: AgentJobs.Programmer,
    cases: [
      no_run: [work: lua(:memory, [:open, :close, :read])],
      no_read: [work: lua(:memory, [:open, :close, :run])],
      no_write: [work: lua(:memory, [:open, :close, :run, :read])]
    ] do
    %{agent: agent, variant: variant, placements: %{work: work}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :work})
      work.seed.("main.lua", ~S|assert(realm.write("report.txt", "new"))|)
      work.seed.("report.txt", "original")

      case variant do
        :no_write ->
          assert %{status: :failed, output: output} =
                   AgentJobs.run_result(agent, :lua, "main.lua")

          assert output =~ "Realm write denied"

        _ ->
          assert {:ok, %{status: :failed, error: %{details: %{reason: :permission_denied}}}} =
                   AgentJobs.run_program(agent, :lua, "main.lua")
      end

      assert work.observe.("report.txt") == {:ok, "original"}
  end

  realm_case "03.01 reject missing toolchains and invalid paths before dispatch",
    agent: AgentJobs.Programmer,
    cases: [files_only: [work: {BindingFixture, kind: :memory}]] do
    %{agent: agent} ->
      refute :lua in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities

      for {entry, opts, expected} <- [
            {"main.lua", %{}, :unsupported_runtime},
            {"../main.lua", %{}, :invalid_path},
            {"main.lua", %{cwd: "../project"}, :invalid_path}
          ] do
        assert {:ok, %{status: :failed, error: %{details: %{reason: ^expected}}}} =
                 AgentJobs.run_program(agent, :lua, entry, opts)
      end
  end

  defp create(agent, path, content) do
    Files.assert_reply(agent, :create, "project/" <> path, %{realm: :work, content: content})
  end

  defp program(:lua) do
    entry = ~S'''
    assert(os == nil and io == nil and debug == nil and package == nil)
    assert(not pcall(loadfile, "data.txt"))
    assert(not pcall(realm.read, "../outside"))
    assert(not pcall(realm.read, "report.txt"))
    assert(realm.write("report.txt", "unpublished draft"))
    local helper = assert(load(realm.read("helper with spaces.lua")))()
    local report = helper(realm.read("data.txt"), arg[1]) .. "\n"
    assert(realm.write("report.txt", report))
    print((realm.read("report.txt"):gsub("\n$", "")))
    '''

    {"main.lua", entry, "helper with spaces.lua", ~S|error("repair the helper")|,
     ~S/return function(data, arg) return "total=" .. data .. " | " .. arg end/}
  end

  defp program(:bash) do
    entry = ~S'''
    set -eu
    test ! -w .
    test ! -e report.txt
    test "$(ls /sys/class/net)" = lo
    printf ok > /tmp/scratch
    source './helper with spaces.sh'
    format_report "$(cat data.txt)" "$1"
    '''

    {"main.sh", entry, "helper with spaces.sh", ~S|printf '%s\n' 'repair the helper' >&2; exit 7|,
     ~S/format_report() { printf 'total=%s | %s\n' "$1" "$2"; }/}
  end

  defp program(:python) do
    entry = ~S'''
    import pathlib
    import sys
    assert not pathlib.Path("report.txt").exists()
    exec(pathlib.Path("helper with spaces.py").read_text())
    print(format_report(pathlib.Path("data.txt").read_text(), sys.argv[1]))
    '''

    {"main.py", entry, "helper with spaces.py", ~S|raise ValueError("repair the helper")|,
     ~S/def format_report(data, arg): return f"total={data} | {arg}"/}
  end

  defp program(:javascript) do
    entry = ~S'''
    const fs = require('node:fs');
    if (fs.existsSync('report.txt')) throw Error('unexpected file');
    const formatReport = require('./helper with spaces.cjs');
    console.log(formatReport(fs.readFileSync('data.txt', 'utf8'), process.argv[2]));
    '''

    {"main.cjs", entry, "helper with spaces.cjs", ~S|throw Error("repair the helper");|,
     ~S/module.exports = (data, arg) => 'total=' + data + ' | ' + arg;/}
  end
end
