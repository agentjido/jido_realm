defmodule Jido.Realm.Conformance.LocalFixture do
  @moduledoc false
  @behaviour Jido.Realm.Conformance.Fixture

  @impl true
  def prepare(_context) do
    suffix = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    root = Path.join(System.tmp_dir!(), "jido-realm-test-" <> suffix)
    File.mkdir!(root)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)

    %{
      runtime_options: [root: root],
      observe: fn path ->
        case File.read(Path.join(root, path)) do
          {:error, :enoent} -> {:error, :not_found}
          result -> result
        end
      end
    }
  end
end
