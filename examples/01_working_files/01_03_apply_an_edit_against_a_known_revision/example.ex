defmodule Jido.Realm.Host.Examples.EditKnownRevision do
  alias Jido.Realm.Host

  def edit(workspace, path, revise) do
    with {:ok, bytes, revision} <- Host.read(workspace, path, revision: true) do
      Host.write(workspace, path, revise.(bytes), expected: revision)
    end
  end
end
