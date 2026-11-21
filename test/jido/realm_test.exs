defmodule Jido.RealmTest do
  use ExUnit.Case, async: true

  alias Jido.Realm.Conformance.Files

  @tag :tmp_dir
  test "Local handles nested files and rejects symlinks", %{tmp_dir: temp} do
    on_exit(fn -> File.rm_rf!(temp) end)
    root = Path.join(temp, "realm")
    File.mkdir_p!(Path.join(root, "nested"))
    outside = Path.join(temp, "outside.txt")
    File.write!(outside, "original")
    File.ln_s!(outside, Path.join(root, "linked-file"))
    File.ln_s!(temp, Path.join(root, "linked-dir"))
    server = Files.start_agent(__MODULE__, root: root)

    Files.assert_reply(server, :create, "nested/inside.txt", %{content: "inside"})
    assert File.read!(Path.join(root, "nested/inside.txt")) == "inside"

    Files.assert_rejected(server, :read, "linked-dir/outside.txt", :invalid_path)
    Files.assert_rejected(server, :edit, "linked-file", :invalid_path, %{content: "edited"})
    assert File.read!(outside) == "original"
  end
end
