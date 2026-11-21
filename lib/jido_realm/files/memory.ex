defmodule Jido.Realm.Memory do
  @moduledoc "Stores a Realm file tree in memory for the life of the store process."

  use Agent

  @behaviour Jido.Realm.FileBackend

  alias Jido.Realm.Tree

  def start_link(opts \\ []), do: Agent.start_link(fn -> %{} end, opts)

  @impl true
  def run(store, :write_stream, path, {chunks, replace}) do
    with {:ok, reversed} <- Tree.ingest(chunks, [], fn parts, chunk -> {:ok, [chunk | parts]} end) do
      content = reversed |> Enum.reverse() |> IO.iodata_to_binary()
      run(store, if(replace, do: :put, else: :create), path, content)
    end
  end

  def run(store, operation, path, input)
      when operation in [:read, :list, :read_revision, :read_coding, :search, :read_stream] do
    Agent.get(store, fn files -> read(files, operation, path, input) end)
  end

  def run(store, operation, path, input) when operation in [:create_revision, :replace_text] do
    Agent.get_and_update(store, fn files ->
      result =
        case operation do
          :create_revision ->
            mutate(files, :create, path, input)

          :replace_text ->
            with {:ok, previous} <- file(files, path),
                 {:ok, content} <- Tree.coding_replace(previous, input) do
              mutate(files, :edit, path, content)
            end
        end

      case result do
        {:ok, updated} ->
          {{:ok, %{revision: Tree.revision(Map.fetch!(updated, path))}}, updated}

        {:error, _} = error ->
          {error, files}
      end
    end)
  end

  def run(store, operation, path, input) do
    Agent.get_and_update(store, fn files ->
      case mutate(files, operation, path, input) do
        {:ok, updated} -> {:ok, updated}
        {:error, _} = error -> {error, files}
      end
    end)
  end

  defp read(files, :read, path, _), do: file(files, path)

  defp read(files, :read_coding, path, _) do
    with {:ok, bytes} <- file(files, path), do: Tree.coding_read(bytes)
  end

  defp read(files, :read_revision, path, _) do
    with {:ok, content} <- file(files, path),
         do: {:ok, %{content: content, revision: Tree.revision(content)}}
  end

  defp read(files, :read_stream, path, chunk_size) do
    with {:ok, content} <- file(files, path) do
      {:ok,
       Stream.unfold(content, fn
         <<>> -> nil
         remaining -> :erlang.split_binary(remaining, min(byte_size(remaining), chunk_size))
       end)}
    end
  end

  defp read(files, :list, path, _) do
    with :ok <- directory(files, path) do
      entries =
        files
        |> Enum.filter(fn {key, _} -> Path.dirname(key) == path end)
        |> Enum.map(fn {key, value} ->
          %{path: key, type: if(value == :directory, do: :directory, else: :file)}
        end)
        |> Enum.sort_by(& &1.path)

      {:ok, %{entries: entries}}
    end
  end

  defp read(files, :search, path, {query, limit}) do
    with :ok <- directory(files, path) do
      candidates =
        files
        |> Enum.filter(fn {key, value} ->
          is_binary(value) and (path == "." or String.starts_with?(key, path <> "/"))
        end)
        |> Enum.sort_by(&elem(&1, 0))

      {:ok, Tree.matches(candidates, query, limit)}
    end
  end

  defp mutate(files, operation, path, value) when operation in [:create, :mkdir] do
    with :ok <- directory(files, Path.dirname(path)),
         :ok <- vacant(files, path) do
      {:ok, Map.put(files, path, if(operation == :mkdir, do: :directory, else: value))}
    end
  end

  defp mutate(files, :put, path, content) do
    case file(files, path) do
      {:ok, _} -> mutate(files, :edit, path, content)
      {:error, :not_found} -> mutate(files, :create, path, content)
      error -> error
    end
  end

  defp mutate(files, :edit, path, content) do
    with {:ok, _} <- file(files, path), do: {:ok, Map.put(files, path, content)}
  end

  defp mutate(files, :delete, path, _) do
    with {:ok, _} <- file(files, path), do: {:ok, Map.delete(files, path)}
  end

  defp mutate(files, :rename, path, destination) do
    with {:ok, content} <- file(files, path),
         :ok <- directory(files, Path.dirname(destination)),
         :ok <- vacant(files, destination) do
      {:ok, files |> Map.delete(path) |> Map.put(destination, content)}
    end
  end

  defp mutate(files, :edit_revision, path, {revision, content}) do
    with :ok <- check_revision(files, path, revision), do: {:ok, Map.put(files, path, content)}
  end

  defp mutate(files, :delete_revision, path, revision) do
    with :ok <- check_revision(files, path, revision), do: {:ok, Map.delete(files, path)}
  end

  defp mutate(_, _, _, _), do: {:error, :unsupported_file_operation}

  defp check_revision(files, path, expected) do
    with {:ok, bytes} <- file(files, path) do
      if Tree.revision(bytes) == expected, do: :ok, else: {:error, :conflict}
    end
  end

  defp file(files, path) do
    with :ok <- directory(files, Path.dirname(path)) do
      case Map.fetch(files, path) do
        {:ok, bytes} when is_binary(bytes) -> {:ok, bytes}
        {:ok, :directory} -> {:error, :not_a_file}
        :error -> {:error, :not_found}
      end
    end
  end

  defp directory(_, "."), do: :ok

  defp directory(files, path) do
    case Map.fetch(files, path) do
      {:ok, :directory} -> :ok
      {:ok, _} -> {:error, :not_a_file}
      :error -> directory(files, Path.dirname(path)) |> missing_directory()
    end
  end

  defp missing_directory(:ok), do: {:error, :not_found}
  defp missing_directory(error), do: error

  defp vacant(files, path) do
    if Map.has_key?(files, path), do: {:error, :already_exists}, else: :ok
  end
end
