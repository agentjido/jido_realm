defmodule Jido.Realm.Placement do
  @moduledoc "File placements for Local and Memory Realms."

  @behaviour Jido.Realm.Provider

  alias Jido.Realm.{Local, Memory}

  @capabilities %{files: true, tree: true, revisions: true, search: true, streams: true}

  @impl true
  def open({:borrow, {backend, _handle} = binding}) when backend in [Local, Memory],
    do: {:ok, lease(binding, :borrowed)}

  def open({:local, root}) when is_binary(root) do
    case File.mkdir(root) do
      :ok -> {:ok, lease({Local, root}, :owned)}
      {:error, reason} -> {:error, reason}
    end
  end

  def open(:memory) do
    with {:ok, store} <- Memory.start_link(), do: {:ok, lease({Memory, store}, :owned)}
  end

  @impl true
  def close(%{ownership: :borrowed}, _opts), do: :ok

  def close(%{binding: {Memory, store}}, _opts) do
    if Process.alive?(store), do: Agent.stop(store), else: :ok
  end

  def close(%{binding: {Local, root}}, _opts) do
    case File.rm_rf(root) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  defp lease({_, handle} = binding, ownership),
    do: %{binding: binding, placement: handle, capabilities: @capabilities, ownership: ownership}
end
