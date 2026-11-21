defmodule Jido.Realm.Conformance.MemoryFixture do
  @moduledoc false
  @behaviour Jido.Realm.Conformance.Fixture

  alias Jido.Realm.Memory

  @impl true
  def prepare(_context) do
    store = ExUnit.Callbacks.start_supervised!(Memory, id: make_ref())

    %{
      runtime_options: [backend: {Memory, store}],
      observe: fn path ->
        case Agent.get(store, &Map.fetch(&1, path)) do
          :error -> {:error, :not_found}
          result -> result
        end
      end
    }
  end
end
