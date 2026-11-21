defmodule Jido.Realm.Conformance.VFSFixture do
  @moduledoc false
  @behaviour Jido.Realm.Conformance.Fixture

  alias Jido.Realm.{Provider, Session}
  alias Jido.VFS
  alias Jido.VFS.Adapter.InMemory

  @impl true
  def prepare(_context) do
    filesystem = InMemory.configure(name: make_ref())
    ExUnit.Callbacks.start_supervised!({InMemory, filesystem}, id: make_ref())

    session =
      ExUnit.Callbacks.start_supervised!({Session, provider: {Provider.VFS, filesystem}},
        id: make_ref()
      )

    %{
      runtime_options: [session: session],
      observe: fn path ->
        case VFS.read(filesystem, path) do
          {:error, %VFS.Errors.FileNotFound{}} -> {:error, :not_found}
          result -> result
        end
      end
    }
  end
end
