defmodule Jido.Realm.Host.Examples.FindProjectFiles do
  alias Jido.Realm.Host

  def inspect_first_match(workspace, directory, marker) do
    with {:ok, [entry | _]} <- Host.find(workspace, directory, contains: marker),
         {:ok, bytes, revision} <- Host.read(workspace, entry.path, revision: true) do
      {:ok, %{entry: entry, bytes: bytes, revision: revision}}
    else
      {:ok, []} -> {:ok, nil}
      error -> error
    end
  end
end
