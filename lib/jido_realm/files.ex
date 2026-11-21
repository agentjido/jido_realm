defmodule Jido.Realm.Files do
  @moduledoc false

  alias Jido.Realm.{FileBackend, FilePath}

  require FileBackend

  @grants %{
    create: :write,
    create_revision: :write,
    replace_text: :write,
    read_coding: :read,
    edit: :write,
    delete: :write,
    mkdir: :write,
    rename: :write,
    edit_revision: :write,
    delete_revision: :write,
    write_stream: :write,
    read: :read,
    list: :read,
    read_revision: :read,
    reconcile: :write,
    search: :read,
    consume: :read
  }

  @capabilities %{
    mkdir: :tree,
    list: :tree,
    rename: :tree,
    read_revision: :revisions,
    read_coding: :revisions,
    create_revision: :revisions,
    replace_text: :revisions,
    edit_revision: :revisions,
    delete_revision: :revisions,
    reconcile: :reconcile,
    search: :search,
    consume: :streams,
    write_stream: :streams
  }

  def grant(operation), do: Map.get(@grants, operation, operation)
  def capability(operation), do: Map.get(@capabilities, operation, :files)
  def mutating?(operation), do: grant(operation) == :write and operation != :reconcile

  def execute({module, handle}, :consume, path, {chunk_size, consume}) do
    with :ok <- FilePath.validate(path),
         {:ok, stream} <- module.run(handle, :read_stream, path, chunk_size),
         do: consume.(stream)
  end

  def execute({module, handle}, operation, path, input) when is_map_key(@grants, operation) do
    with :ok <- validate_paths(operation, path, input),
         {:ok, value} <- input_content(operation, input) do
      file_result(operation, path, module.run(handle, operation, path, value))
    end
  end

  def execute(_, _, _, _), do: {:error, :unsupported_file_operation}

  def validate_stream_options(chunk_size, replace)
      when is_integer(chunk_size) and chunk_size in 1..1_048_576 and is_boolean(replace),
      do: :ok

  def validate_stream_options(_, _), do: {:error, :invalid_file_options}

  def validate_paths(:rename, path, destination) do
    with :ok <- FilePath.validate(path), do: FilePath.validate(destination)
  end

  def validate_paths(operation, ".", _) when operation in [:list, :search], do: :ok
  def validate_paths(_, path, _), do: FilePath.validate(path)

  defp input_content(operation, content) when operation in [:create, :edit], do: text(content)

  defp input_content(:create_revision, content), do: Jido.Realm.Tree.coding_text(content)

  defp input_content(:replace_text, {revision, old, new})
       when is_binary(revision) and byte_size(revision) <= 128 and old != "" do
    with {:ok, old} <- Jido.Realm.Tree.coding_text(old),
         {:ok, new} <- Jido.Realm.Tree.coding_text(new),
         do: {:ok, {revision, old, new}}
  end

  defp input_content(:rename, path), do: {:ok, path}

  defp input_content(:search, {query, limit})
       when is_binary(query) and query != "" and is_integer(limit) and limit in 1..1_000,
       do: {:ok, {query, limit}}

  defp input_content(:edit_revision, {revision, content}) when is_binary(revision) do
    with {:ok, value} <- text(content), do: {:ok, {revision, value}}
  end

  defp input_content(:delete_revision, revision) when is_binary(revision), do: {:ok, revision}

  defp input_content(:reconcile, request_id) when is_binary(request_id) and request_id != "",
    do: {:ok, request_id}

  defp input_content(:write_stream, {_, replace} = input) when is_boolean(replace),
    do: {:ok, input}

  defp input_content(operation, _)
       when operation in [:read, :delete, :mkdir, :list, :read_revision, :read_coding],
       do: {:ok, nil}

  defp input_content(_, _), do: {:error, :invalid_file_options}

  defp file_result(_, _, {:error, reason} = error) when FileBackend.is_file_error(reason),
    do: error

  defp file_result(_, _, {:error, {:unknown, request_id}} = error) when is_binary(request_id),
    do: error

  defp file_result(:read, path, {:ok, content}) when is_binary(content) do
    with {:ok, content} <- text(content),
         do: {:ok, %{operation: :read, path: path, content: content}}
  end

  defp file_result(:read_revision, path, {:ok, %{content: content, revision: revision}}) do
    with {:ok, content} <- text(content),
         do: {:ok, %{operation: :read_revision, path: path, content: content, revision: revision}}
  end

  defp file_result(operation, path, {:ok, data})
       when operation in [
              :list,
              :search,
              :reconcile,
              :read_coding,
              :create_revision,
              :replace_text
            ] and is_map(data),
       do: {:ok, Map.merge(data, %{operation: operation, path: path})}

  defp file_result(operation, path, {:ok, %{commit: commit}})
       when operation in [:create, :edit, :delete, :edit_revision, :delete_revision] and
              is_binary(commit),
       do: {:ok, %{operation: operation, path: path, commit: commit}}

  defp file_result(operation, path, :ok), do: {:ok, %{operation: operation, path: path}}
  defp file_result(_, _, _), do: {:error, :backend_error}

  defp text(nil), do: {:error, :content_required}

  defp text(content) when is_binary(content),
    do: if(String.valid?(content), do: {:ok, content}, else: {:error, :invalid_text})

  defp text(_content), do: {:error, :invalid_text}
end
