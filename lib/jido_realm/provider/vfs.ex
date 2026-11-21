defmodule Jido.Realm.Provider.VFS do
  @moduledoc """
  Borrows a host-owned Jido VFS filesystem that supports atomic capture
  and checked edits. Realm exposes basic file operations on this binding.
  The host starts the store and controls its lifetime.
  """

  alias Jido.VFS

  @behaviour Jido.Realm.Provider
  @behaviour Jido.Realm.FileBackend

  @impl Jido.Realm.Provider
  def open({adapter, _} = filesystem) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) and
         Enum.all?([:capture, :apply_edits], &VFS.supports?(filesystem, &1)) do
      {:ok,
       %{
         binding: {__MODULE__, filesystem},
         placement: filesystem,
         capabilities: %{files: true},
         ownership: :borrowed
       }}
    else
      {:error, :unsupported_vfs_binding}
    end
  end

  def open(_), do: {:error, :unsupported_vfs_binding}

  @impl Jido.Realm.Provider
  def close(_lease, _options), do: :ok

  @impl Jido.Realm.FileBackend
  def run(filesystem, :read, path, _) do
    with {:ok, capture, _token} <- VFS.capture(filesystem),
         {:ok, entries} <- VFS.entries(capture),
         do: contents(entries[path])
  end

  def run(filesystem, operation, path, content) when operation in [:create, :edit, :delete],
    do: apply_change(filesystem, operation, path, content, 8)

  def run(_, _, _, _), do: {:error, :unsupported_file_operation}

  defp apply_change(_, _, _, _, 0), do: {:error, :conflict}

  defp apply_change(filesystem, operation, path, content, remaining) do
    with {:ok, capture, token} <- VFS.capture(filesystem),
         {:ok, entries} <- VFS.entries(capture),
         {:ok, edit} <- edit(operation, entries, path, content),
         {:ok, _next_token} <- VFS.apply_edits(filesystem, token, [edit]) do
      :ok
    else
      {:error, %VFS.Errors.StaleState{}} ->
        apply_change(filesystem, operation, path, content, remaining - 1)

      {:error, reason} when is_atom(reason) ->
        {:error, reason}

      {:error, _} ->
        {:error, :backend_error}
    end
  end

  defp edit(:create, entries, path, content) do
    with :ok <- parent_directory(entries, Path.dirname(path)),
         nil <- entries[path] do
      {:ok, {:write, path, content}}
    else
      %{} -> {:error, :already_exists}
      {:error, _} = error -> error
    end
  end

  defp edit(operation, entries, path, content) do
    with {:ok, _} <- contents(entries[path]) do
      {:ok, if(operation == :delete, do: {:delete, path}, else: {:write, path, content})}
    end
  end

  defp contents(%{type: :file, content: content}), do: {:ok, content}
  defp contents(%{type: :directory}), do: {:error, :not_a_file}
  defp contents(nil), do: {:error, :not_found}

  defp parent_directory(_entries, "."), do: :ok

  defp parent_directory(entries, path) do
    case entries[path] do
      %{type: :directory} -> :ok
      %{type: :file} -> {:error, :not_a_file}
      nil -> {:error, :not_found}
    end
  end
end
