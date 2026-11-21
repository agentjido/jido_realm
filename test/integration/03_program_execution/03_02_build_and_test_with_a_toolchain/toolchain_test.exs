defmodule Jido.Realm.Integration.ToolchainTest do
  use ExUnit.Case

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}
  alias Jido.Realm.Runner

  @tag :docker
  test "03.02 tests a source file, saves compiled Python bytecode, and executes that exact file",
       context do
    image = System.get_env("JIDO_REALM_PYTHON_IMAGE", "python:3.13-alpine")
    docker = {Runner.Docker, image: image, context: System.get_env("JIDO_REALM_DOCKER_CONTEXT")}
    binding = {BindingFixture, kind: :local, runners: %{python: docker}}

    %{agent: agent, observe: %{work: observe}} =
      Scenarios.prepare(context, AgentJobs.Programmer, [work: binding], :docker)

    assert :python in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities

    Files.assert_reply(agent, :mkdir, "project folder", %{realm: :work})

    Files.assert_reply(agent, :create, "project folder/build.py", %{
      realm: :work,
      content: """
      import base64, pathlib, py_compile, runpy, sys
      source = sys.argv[1]
      result = runpy.run_path(source, run_name='candidate')
      assert result['answer']() == 42, 'wrong answer'
      path = pathlib.Path('/tmp/result.pyc')
      py_compile.compile(source, cfile=str(path), doraise=True)
      print(base64.b64encode(path.read_bytes()).decode('ascii'))
      """
    })

    source = "project folder/source with spaces.py"
    original = "def answer(): return 41\nif __name__ == '__main__': print(answer())\n"
    Files.assert_reply(agent, :create, source, %{realm: :work, content: original})
    output = "project folder/release.pyc"

    opts = %{
      cwd: "project folder",
      args: ["source with spaces.py"],
      inputs: ["source with spaces.py"],
      timeout_ms: 5_000
    }

    assert %{status: :failed, output: diagnostics} =
             AgentJobs.run_result(agent, :python, "build.py", opts)

    assert diagnostics =~ "wrong answer"
    assert observe.(output) == {:error, :not_found}

    Files.assert_reply(agent, :edit, source, %{
      realm: :work,
      content: String.replace(original, "41", "42")
    })

    assert %{status: :succeeded, truncated: false, output: compiled, id: build_id} =
             AgentJobs.run_result(agent, :python, "build.py", opts)

    AgentJobs.succeeded(agent, :save_binary, %{realm: :work, path: output, text: compiled})
    assert observe.(output) == {:ok, Base.decode64!(String.trim(compiled))}
    refute String.valid?(elem(observe.(output), 1))

    Files.assert_reply(agent, :delete, source, %{realm: :work})

    assert %{status: :succeeded, output: "42\n", id: run_id} =
             AgentJobs.run_result(agent, :python, "release.pyc", %{
               cwd: "project folder",
               timeout_ms: 5_000
             })

    refute build_id == run_id
    assert observe.(source) == {:error, :not_found}
    AgentJobs.succeeded(agent, :close, %{realm: :work})
  end
end
