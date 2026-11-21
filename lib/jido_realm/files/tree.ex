defmodule Jido.Realm.Tree do
  @moduledoc false

  def revision(bytes), do: Base.url_encode64(:crypto.hash(:sha256, bytes), padding: false)

  @coding_limit 1_048_576

  def coding_limit, do: @coding_limit

  def coding_text(bytes) when is_binary(bytes) and byte_size(bytes) <= @coding_limit do
    if String.valid?(bytes), do: {:ok, bytes}, else: {:error, :invalid_text}
  end

  def coding_text(bytes) when is_binary(bytes), do: {:error, :input_limit}
  def coding_text(_), do: {:error, :invalid_text}

  def coding_read(bytes) do
    with {:ok, bytes} <- coding_text(bytes),
         do: {:ok, %{content: bytes, revision: revision(bytes)}}
  end

  def coding_replace(bytes, {expected, old, new}) do
    with {:ok, %{revision: actual}} <- coding_read(bytes),
         true <- expected == actual do
      case :binary.match(bytes, old) do
        :nomatch ->
          {:error, :text_not_found}

        {offset, size} ->
          tail = binary_part(bytes, offset + 1, byte_size(bytes) - offset - 1)

          if :binary.match(tail, old) == :nomatch do
            prefix = binary_part(bytes, 0, offset)
            suffix = binary_part(bytes, offset + size, byte_size(bytes) - offset - size)
            coding_text(prefix <> new <> suffix)
          else
            {:error, :ambiguous_match}
          end
      end
    else
      false -> {:error, :conflict}
      error -> error
    end
  end

  def matches(files, query, limit) do
    paths =
      files
      |> Stream.filter(fn {_path, bytes} ->
        String.valid?(bytes) and :binary.match(bytes, query) != :nomatch
      end)
      |> Stream.map(fn {path, _bytes} -> path end)
      |> Enum.take(limit + 1)

    %{matches: Enum.take(paths, limit), limit: limit, truncated: length(paths) > limit}
  end

  def ingest(chunks, initial, append) do
    Enum.reduce_while(chunks, {:ok, initial}, fn
      chunk, {:ok, state} when is_binary(chunk) ->
        case append.(state, chunk) do
          {:ok, _} = next -> {:cont, next}
          {:error, _} = error -> {:halt, error}
        end

      _, _ ->
        {:halt, {:error, :transfer_interrupted}}
    end)
  rescue
    File.Error -> {:error, :transfer_interrupted}
  end
end
