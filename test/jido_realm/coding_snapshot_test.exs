defmodule Jido.Realm.CodingSnapshotTest do
  use ExUnit.Case, async: true

  alias Jido.Realm.{Local, Tree}
  alias Jido.Realm.Runner.Snapshot

  @tag :tmp_dir
  test "capture waits for a writer and preserves the coherent bytes", %{tmp_dir: tmp} do
    root = Path.join(tmp, "source")
    stage = Path.join(tmp, "snapshot")
    File.mkdir!(root)
    File.mkdir!(stage)
    File.write!(Path.join(root, "first.ex"), "old first")
    File.write!(Path.join(root, "second.ex"), "old second")
    test = self()

    writer =
      Task.async(fn ->
        Local.with_lock(root, fn ->
          File.write!(Path.join(root, "first.ex"), "new first")
          send(test, :partial_write)

          receive do
            :commit -> File.write!(Path.join(root, "second.ex"), "new second")
          end
        end)
      end)

    assert_receive :partial_write
    hello = %{image: "pinned image"}
    input = %{files: ["first.ex", "second.ex"], directories: []}
    capture = Task.async(fn -> Snapshot.capture(root, input, hello, stage) end)
    assert Task.yield(capture, 50) == nil

    send(writer.pid, :commit)
    assert :ok = Task.await(writer)
    assert {:ok, %{inputs: hashes, toolchain: ^hello}} = Task.await(capture)

    assert hashes == %{
             "first.ex" => Tree.revision("new first"),
             "second.ex" => Tree.revision("new second")
           }

    assert :ok = Local.run(root, :edit, "first.ex", "later edit")
    assert File.read!(Path.join(stage, "first.ex")) == "new first"
    assert File.read!(Path.join(stage, "second.ex")) == "new second"
  end
end
