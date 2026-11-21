defmodule Jido.Realm.Local do
  @moduledoc false

  @behaviour Jido.Realm.FileBackend

  alias Jido.Realm.{FilePath, Tree}

  require Jido.Realm.FileBackend

  @errors %{
    eexist: :already_exists,
    enoent: :not_found,
    enotdir: :not_a_file,
    not_regular_file: :not_a_file,
    eacces: :permission_denied,
    eperm: :permission_denied,
    symlink: :invalid_path
  }

  @impl true
  def run(root, operation, path, content) do
    root = Path.expand(root)
    components = String.split(path, "/")
    result = with_lock(root, fn -> run_locked(root, components, operation, content) end)

    case result do
      {:error, reason} = error when Jido.Realm.FileBackend.is_file_error(reason) -> error
      {:error, reason} -> {:error, Map.get(@errors, reason, :backend_error)}
      :aborted -> {:error, :backend_error}
      success -> success
    end
  end

  # Capture and writes take the same lock across sessions on this node.
  def with_lock(root, fun),
    do: :global.trans({{__MODULE__, Path.expand(root)}, self()}, fun, [node()])

  def captured_file(root, operation, path),
    do: run_locked(root, String.split(path, "/"), operation, nil)

  defp run_locked(root, components, :rename, destination) do
    with {:ok, source} <- resolve(root, components),
         {:ok, target} <- resolve(root, String.split(destination, "/")),
         {:ok, _} <- regular_file(source),
         :ok <- File.ln(source, target) do
      case File.rm(source) do
        :ok ->
          :ok

        error ->
          File.rm(target)
          error
      end
    end
  end

  defp run_locked(root, components, operation, input) when operation in [:list, :search] do
    path = Enum.join(components, "/")

    with {:ok, file} <- resolve(root, components),
         {:ok, result} <- operate(operation, file, input) do
      {:ok, prefix_paths(result, path)}
    end
  end

  defp run_locked(root, components, operation, input) do
    with {:ok, file} <- resolve(root, components), do: operate(operation, file, input)
  end

  defp prefix_paths(result, "."), do: result

  defp prefix_paths(%{entries: entries} = result, path) do
    %{
      result
      | entries:
          Enum.map(entries, &Map.update!(&1, :path, fn child -> Path.join(path, child) end))
    }
  end

  defp prefix_paths(%{matches: matches} = result, path) do
    %{result | matches: Enum.map(matches, &Path.join(path, &1))}
  end

  defp resolve(directory, components) do
    case File.lstat(directory) do
      {:ok, %{type: :directory}} ->
        case components do
          ["."] -> {:ok, directory}
          [name] -> {:ok, Path.join(directory, name)}
          [name | rest] -> resolve(Path.join(directory, name), rest)
        end

      {:ok, %{type: :symlink}} ->
        {:error, :symlink}

      {:ok, _} ->
        {:error, :enotdir}

      {:error, _} = error ->
        error
    end
  end

  defp operate(:create, file, content) do
    stage(file, content, &File.ln(&1, file))
  end

  defp operate(:read, file, _content) do
    with {:ok, _stat} <- regular_file(file), do: File.read(file)
  end

  defp operate(:edit, file, content) do
    with {:ok, stat} <- regular_file(file) do
      stage(file, content, &replace(&1, file, stat.mode))
    end
  end

  defp operate(:delete, file, _content) do
    with {:ok, _stat} <- regular_file(file), do: File.rm(file)
  end

  defp operate(:mkdir, file, _), do: File.mkdir(file)

  defp operate(:list, file, _) do
    with {:ok, entries} <- entries(file) do
      {:ok, %{entries: Enum.map(entries, fn {name, type} -> %{path: name, type: type} end)}}
    end
  end

  defp operate(:search, directory, {query, limit}) do
    with {:ok, _} <- entries(directory) do
      candidates =
        Stream.resource(
          fn -> ["."] end,
          fn
            [] ->
              {:halt, []}

            [path | rest] ->
              absolute = Path.join(directory, path)

              case File.lstat(absolute) do
                {:ok, %{type: :directory}} ->
                  {[], queue_search_children(absolute, path, rest)}

                {:ok, %{type: :regular}} ->
                  case File.read(absolute) do
                    {:ok, value} -> {[{path, value}], rest}
                    {:error, _} -> {[], rest}
                  end

                _ ->
                  {[], rest}
              end
          end,
          fn _ -> :ok end
        )

      {:ok, Tree.matches(candidates, query, limit)}
    end
  end

  defp operate(:read_coding, file, _) do
    with {:ok, stat} <- regular_file(file),
         true <- stat.size <= Tree.coding_limit(),
         {:ok, bytes} <- File.read(file) do
      Tree.coding_read(bytes)
    else
      false -> {:error, :input_limit}
      error -> error
    end
  end

  defp operate(:create_revision, file, bytes) do
    with :ok <- operate(:create, file, bytes), do: {:ok, %{revision: Tree.revision(bytes)}}
  end

  defp operate(:replace_text, file, input) do
    with {:ok, %{content: previous}} <- operate(:read_coding, file, nil),
         {:ok, bytes} <- Tree.coding_replace(previous, input),
         :ok <- operate(:edit, file, bytes) do
      {:ok, %{revision: Tree.revision(bytes)}}
    end
  end

  defp operate(:read_revision, file, _) do
    with {:ok, content} <- operate(:read, file, nil),
         do: {:ok, %{content: content, revision: Tree.revision(content)}}
  end

  defp operate(:edit_revision, file, {revision, content}) do
    with :ok <- check_revision(file, revision), do: operate(:edit, file, content)
  end

  defp operate(:delete_revision, file, revision) do
    with :ok <- check_revision(file, revision), do: operate(:delete, file, nil)
  end

  defp operate(:read_stream, file, chunk_size) do
    with {:ok, _} <- regular_file(file), do: {:ok, File.stream!(file, chunk_size)}
  end

  defp operate(:write_stream, file, {chunks, replace?}) do
    write_staged(
      file,
      fn device ->
        case Tree.ingest(chunks, device, fn io, chunk ->
               with :ok <- IO.binwrite(io, chunk), do: {:ok, io}
             end) do
          {:ok, _} -> :ok
          {:error, _} = error -> error
        end
      end,
      fn staged -> publish_stream(staged, file, replace?) end
    )
  end

  defp operate(_, _, _), do: {:error, :unsupported_file_operation}

  defp queue_search_children(absolute, path, rest) do
    case entries(absolute) do
      {:ok, children} ->
        paths =
          Enum.map(children, fn {name, _} ->
            if path == ".", do: name, else: Path.join(path, name)
          end)

        paths ++ rest

      {:error, _} ->
        rest
    end
  end

  defp publish_stream(staged, file, false), do: File.ln(staged, file)

  defp publish_stream(staged, file, true) do
    case regular_file(file) do
      {:ok, stat} -> replace(staged, file, stat.mode)
      {:error, :enoent} -> File.ln(staged, file)
      error -> error
    end
  end

  defp check_revision(file, revision) do
    case operate(:read_revision, file, nil) do
      {:ok, %{revision: ^revision}} -> :ok
      {:ok, _} -> {:error, :conflict}
      error -> error
    end
  end

  defp entries(directory) do
    case File.lstat(directory) do
      {:ok, %{type: :directory}} ->
        with {:ok, names} <- File.ls(directory) do
          {:ok,
           for(
             name <- Enum.sort(names),
             FilePath.validate(name) == :ok,
             {:ok, %{type: type}} <- [File.lstat(Path.join(directory, name))],
             type in [:regular, :directory],
             do: {name, if(type == :regular, do: :file, else: type)}
           )}
        end

      {:ok, %{type: :symlink}} ->
        {:error, :symlink}

      {:ok, _} ->
        {:error, :enotdir}

      error ->
        error
    end
  end

  defp regular_file(file) do
    case File.lstat(file) do
      {:ok, %{type: :regular}} = result -> result
      {:ok, %{type: :symlink}} -> {:error, :symlink}
      {:ok, _} -> {:error, :not_regular_file}
      {:error, _} = error -> error
    end
  end

  defp stage(file, content, publish), do: write_staged(file, &IO.binwrite(&1, content), publish)

  defp write_staged(file, write, publish) do
    staged = Path.join(Path.dirname(file), FilePath.staging_name())

    with {:ok, device} <- File.open(staged, [:write, :binary, :exclusive]) do
      try do
        written = write.(device)
        closed = File.close(device)

        with :ok <- written, :ok <- closed, do: publish.(staged)
      after
        if Process.alive?(device), do: File.close(device)
        File.rm(staged)
      end
    end
  end

  defp replace(staged, file, mode) do
    with :ok <- File.chmod(staged, Bitwise.band(mode, 0o777)) do
      File.rename(staged, file)
    end
  end
end
