Code.require_file("../../05_lifecycle/support.exs", __DIR__)
Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.FollowOutputTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Error, Execution}
  alias Jido.Realm.Host.Examples.FollowOutput
  import Jido.Realm.Host.Examples.LifecycleSupport

  setup %{tmp_dir: root}, do: configure(root)

  test "memory streams before exit and reports a gap after an observer waits" do
    assert {:ok, workspace} = Host.open(profile: :memory)

    task =
      Task.async(fn ->
        Host.run(workspace, ["sleep", "30"], timeout_ms: 20_000, output_limit: 4)
      end)

    id = running_id(workspace)

    first =
      await(
        fn ->
          case Host.output(workspace, id) do
            {:ok, %{bytes: "...\n", done?: false} = slice} -> slice
            _ -> nil
          end
        end,
        "The running virtual command did not emit bytes"
      )

    assert first.dropped_bytes == first.next_offset - 4

    later =
      await(
        fn ->
          case Host.output(workspace, id, first.next_offset) do
            {:ok, %{dropped_bytes: dropped, done?: false} = slice} when dropped > 0 -> slice
            _ -> nil
          end
        end,
        "The observer did not fall behind",
        4_000
      )

    assert byte_size(later.bytes) == 4
    assert later.next_offset == first.next_offset + later.dropped_bytes + 4
    assert :ok = Host.cancel(workspace, id)

    assert {:ok, %Execution{id: ^id, status: :cancelled, output: "Slee", truncated: true}} =
             Task.await(task)

    assert {:ok, %{done?: true, next_offset: last}} =
             Host.output(workspace, id, later.next_offset)

    assert last >= later.next_offset
    assert :ok = Host.close(workspace)
    assert {:error, %Error{code: :closed}} = Host.output(workspace, id)
  end

  test "a zero-byte limit reports a gap and a new command replaces the record" do
    assert {:ok, workspace} = Host.open(profile: :memory)

    assert {:ok, %Execution{id: id, output: "", truncated: true}} =
             Host.run(workspace, ["echo", "abc"], output_limit: 0)

    assert {:ok, %{bytes: "", next_offset: 4, dropped_bytes: 4, done?: true}} =
             Host.output(workspace, id)

    assert {:ok, %Execution{id: next_id}} = Host.run(workspace, ["echo", "next"])
    assert {:error, %Error{code: :output_unavailable}} = Host.output(workspace, id)
    assert {:ok, %{bytes: "next\n", done?: true}} = Host.output(workspace, next_id)
    assert :ok = Host.close(workspace)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to check live Docker output"
  end

  test "Docker observers can read independently, detect a gap, and drain the final bytes" do
    assert {:ok, workspace} = Host.open(profile: :docker)
    {_controller, sandbox} = provider(workspace, :native)
    clean_up_docker_on_failure(sandbox)

    script = """
    mkfifo /tmp/advance /tmp/finish
    printf abcd
    read -r line </tmp/advance
    printf efghijklmnop
    read -r line </tmp/finish
    printf qr
    """

    task =
      Task.async(fn ->
        Host.run(workspace, ["sh", "-c", script], timeout_ms: 20_000, output_limit: 4)
      end)

    id = running_id(workspace)
    container = await(fn -> container_running(sandbox) end, "No running container", 10_000)
    wait_for_offset(workspace, id, 4)
    first = %{bytes: "abcd", next_offset: 4, dropped_bytes: 0, done?: false}
    assert [^first] = workspace |> FollowOutput.follow(id) |> Enum.take(1)
    assert {:ok, ^first} = Host.output(workspace, id)
    assert {:error, %Error{code: :invalid_input}} = Host.output(workspace, id, 5)

    assert {_, 0} = docker(["exec", container, "sh", "-c", ~S(printf 'go\n' >/tmp/advance)])
    wait_for_offset(workspace, id, 16)

    assert {:ok, %{bytes: "mnop", next_offset: 16, dropped_bytes: 8, done?: false}} =
             Host.output(workspace, id, 4)

    assert {:ok, %{bytes: "mnop", next_offset: 16, dropped_bytes: 12, done?: false}} =
             Host.output(workspace, id)

    assert {:ok, %{bytes: "", next_offset: 16, dropped_bytes: 0, done?: false}} =
             Host.output(workspace, id, 16)

    # The main process can exit and stop the exec helper as it releases the pipe.
    assert {_, status} = docker(["exec", container, "sh", "-c", ~S(printf 'go\n' >/tmp/finish)])
    assert status in [0, 137]

    assert {:ok, %Execution{id: ^id, status: :exited, output: "abcd", truncated: true}} =
             Task.await(task, 10_000)

    last = %{bytes: "qr", next_offset: 18, dropped_bytes: 0, done?: true}
    assert [^last] = workspace |> FollowOutput.follow(id, 16) |> Enum.to_list()
    assert :ok = Host.close(workspace)
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

  defp wait_for_offset(workspace, id, offset) do
    await(
      fn ->
        match?({:ok, %{next_offset: ^offset, done?: false}}, Host.output(workspace, id))
      end,
      "The running command did not reach byte offset #{offset}",
      5_000
    )
  end
end
