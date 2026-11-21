Code.require_file("../../05_lifecycle/support.exs", __DIR__)
Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.AnswerPromptTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Error, Execution}
  alias Jido.Realm.Host.Examples.AnswerPrompt
  import Jido.Realm.Host.Examples.LifecycleSupport

  setup %{tmp_dir: root} do
    configure(root)
    profiles = Application.fetch_env!(:jido_realm, :profiles)
    profiles = put_in(profiles, [:docker, :require, :stdin], :pipe)
    memory = Map.put(profiles.memory, :require, %{stdin: :pipe})
    Application.put_env(:jido_realm, :profiles, Map.put(profiles, :memory_pipe, memory))
  end

  test "memory refuses a required pipe and keeps ordinary commands available" do
    assert {:error, %Error{code: :unsupported_capability}} =
             Host.open(profile: :memory_pipe)

    assert {:ok, workspace} = Host.open(profile: :memory)

    assert {:error, %Error{code: :unsupported_capability}} =
             Host.run(workspace, ["echo", "hi"], stdin: :pipe)

    assert {:error, %Error{code: :invalid_input, details: %{step_index: 2}}} =
             Host.batch(workspace, [
               {:mkdir, "unused"},
               {:run, ["echo", "hi"], [stdin: :pipe]}
             ])

    assert {:ok, []} = Host.list(workspace)

    assert {:ok, %Execution{exit_status: 0, output: "hi\n"}} =
             Host.run(workspace, ["echo", "hi"])

    assert :ok = Host.close(workspace)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to send input to a native command"
  end

  test "Docker reads live input and places its result in the workspace" do
    {workspace, sandbox} = open_docker()
    assert :ok = :sys.suspend(sandbox.pid)
    task = Task.async(fn -> AnswerPrompt.run(workspace) end)

    id =
      try do
        id = running_id(workspace)
        assert {:error, %Error{code: :input_not_ready}} = Host.input(workspace, id, "hey\n")
        id
      after
        :sys.resume(sandbox.pid)
      end

    prompt = await_prompt(workspace, id, "name?\n")
    literal = "Ada $(printf ignored)" <> <<16, 17>>
    reply = "hello " <> literal <> "\n"
    full = prompt.bytes <> reply

    assert {:error, %Error{code: :execution_not_active}} =
             Host.input(workspace, "old-id", "wrong\n")

    assert {:error, %Error{code: :invalid_input}} =
             Host.input(workspace, id, :binary.copy("x", 16_385))

    assert :ok = AnswerPrompt.answer(workspace, id, literal)
    assert {:ok, %Execution{id: ^id, exit_status: 0, output: ^full}} = Task.await(task, 10_000)

    assert {:ok, %{bytes: ^reply, done?: true}} =
             Host.output(workspace, id, prompt.next_offset)

    assert {:error, %Error{code: :execution_not_active}} =
             Host.input(workspace, id, "late\n")

    assert {:ok, stored} = Host.read(workspace, "name.txt")
    assert stored == literal <> "\n"
    assert :ok = Host.close(workspace)
    assert [] = containers(sandbox)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to cancel a command with a pipe"
  end

  test "cancellation closes the pipe before the provider confirms the stop" do
    {workspace, sandbox} = open_docker()
    task = Task.async(fn -> AnswerPrompt.run(workspace) end)
    id = running_id(workspace)
    await_prompt(workspace, id, "name?\n")
    assert :ok = :sys.suspend(sandbox.pid)

    try do
      assert :ok = Host.cancel(workspace, id)
      assert {:error, %Error{code: :input_closed}} = Host.input(workspace, id, "late\n")
      assert {:error, %Error{code: :busy}} = Host.save(workspace)
    after
      :sys.resume(sandbox.pid)
    end

    assert {:ok, %Execution{id: ^id, status: :cancelled, output: "name?\n"}} =
             Task.await(task, 10_000)

    assert [] = containers(sandbox)
    assert {:error, %Error{code: :not_found}} = Host.read(workspace, "name.txt")
    assert {:ok, %{kind: "snapshot"}} = Host.save(workspace)
    assert :ok = Host.close(workspace)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to check cleanup on disconnect"
  end

  test "disconnect stops the runtime and keeps writes fenced until cleanup is confirmed" do
    {workspace, sandbox} = open_docker()

    script = ~S"""
    printf 'started\n' > started.txt
    mkfifo /tmp/child-finish
    (read -r ignored </tmp/child-finish && printf late > late.txt) &
    printf 'ready\n'
    read -r ignored
    wait
    """

    {client, monitor} =
      spawn_monitor(fn ->
        Host.run(workspace, ["sh", "-c", script], stdin: :pipe, timeout_ms: 20_000)
      end)

    id = running_id(workspace)
    await_prompt(workspace, id, "ready\n")
    assert [_] = containers(sandbox, ["--filter", "status=running"])
    assert :ok = :sys.suspend(sandbox.pid)

    try do
      assert Process.exit(client, :shutdown)
      assert_receive {:DOWN, ^monitor, :process, ^client, :shutdown}

      await(
        fn ->
          match?({:error, %Error{code: :input_closed}}, Host.input(workspace, id, "probe"))
        end,
        "The controller did not close the input pipe after disconnect"
      )

      assert {:error, %Error{code: :busy}} = Host.write(workspace, "other.txt", "Other")
      assert {:error, %Error{code: :busy}} = Host.save(workspace)
    after
      :sys.resume(sandbox.pid)
    end

    await(
      fn -> match?({:ok, %{phase: :ready}}, Host.info(workspace)) end,
      "The controller did not confirm the stop",
      10_000
    )

    assert [] = containers(sandbox)
    assert {:ok, %{bytes: "ready\n", done?: true}} = Host.output(workspace, id)
    assert {:ok, "started\n"} = Host.read(workspace, "started.txt")
    assert {:error, %Error{code: :not_found}} = Host.read(workspace, "late.txt")
    assert {:ok, %{kind: "snapshot"}} = Host.save(workspace)
    assert :ok = Host.close(workspace)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to close an interactive workspace"
  end

  test "workspace close requests a stop from a command that is waiting for input" do
    {workspace, sandbox} = open_docker()
    task = Task.async(fn -> AnswerPrompt.run(workspace) end)
    id = running_id(workspace)
    await_prompt(workspace, id, "name?\n")

    assert :ok = Host.close(workspace, timeout_ms: 10_000)
    assert {:ok, %Execution{id: ^id, status: :cancelled}} = Task.await(task)
    assert [] = containers(sandbox)
    assert {:error, %Error{code: :closed}} = Host.input(workspace, id, "late\n")
  end

  defp open_docker do
    assert {:ok, workspace} = Host.open(profile: :docker)
    {_controller, sandbox} = provider(workspace, :native)
    clean_up_docker_on_failure(sandbox)
    {workspace, sandbox}
  end

  defp running_id(workspace) do
    await(
      fn ->
        case Host.info(workspace) do
          {:ok, %{phase: :running, active_execution_id: id}} -> id
          _ -> nil
        end
      end,
      "The command did not start"
    )
  end

  defp await_prompt(workspace, id, text) do
    await(
      fn ->
        case Host.output(workspace, id) do
          {:ok, %{bytes: ^text, done?: false} = slice} -> slice
          _ -> nil
        end
      end,
      "The program did not send its prompt",
      10_000
    )
  end
end
