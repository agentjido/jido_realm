defmodule Jido.Realm.Artifacts do
  @moduledoc """
  Presents saved versions of HTML bundles independently of their Realm sessions.

  The host starts a store for an approved audience and sets its retention.
  Each read takes a viewer identity established by the host. Serve the result
  from a dedicated artifact origin using the returned headers.
  Stores are bounded and live for the lifetime of their process.

  A different presenter can implement `publish/3` to use host-managed storage.
  """

  use GenServer

  alias Jido.Realm.{FilePath, Tree}

  @max_files 32
  @max_bytes 1_048_576
  @media_types %{
    ".html" => "text/html; charset=utf-8",
    ".css" => "text/css; charset=utf-8",
    ".js" => "text/javascript; charset=utf-8",
    ".json" => "application/json; charset=utf-8",
    ".txt" => "text/plain; charset=utf-8"
  }

  @type artifact_reference :: %{
          id: String.t(),
          revision: String.t(),
          entrypoint: String.t(),
          media_type: String.t()
        }
  @type bundle :: %{optional(String.t()) => String.t()}
  @callback publish(term(), String.t(), bundle()) ::
              {:ok, artifact_reference()} | {:error, term()}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Stores a bundle and returns a reference to its immutable version."
  def publish(store, entrypoint, files), do: GenServer.call(store, {:publish, entrypoint, files})

  @doc "Reads one file as a host-authenticated viewer. Omit the path to read the entry page."
  def read(store, viewer, id, path \\ nil), do: GenServer.call(store, {:read, viewer, id, path})

  @doc "Revokes access to a previously published version."
  def revoke(store, id), do: GenServer.call(store, {:revoke, id})

  @doc false
  def capture(entrypoint, paths, read) do
    with :ok <- validate_bundle(entrypoint, paths) do
      paths
      |> Enum.reduce_while({:ok, %{}, 0}, fn path, {:ok, files, size} ->
        case read.(path) do
          {:ok, %{content: bytes}} when size + byte_size(bytes) <= @max_bytes ->
            {:cont, {:ok, Map.put(files, path, bytes), size + byte_size(bytes)}}

          {:ok, _} ->
            {:halt, {:error, :artifact_too_large}}

          {:error, _} = error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, files, _} -> {:ok, files}
        error -> error
      end
    end
  end

  @impl true
  def init(opts) do
    viewers = opts |> Keyword.fetch!(:viewers) |> MapSet.new()
    retention_ms = Keyword.get(opts, :retention_ms, 3_600_000)
    max_artifacts = Keyword.get(opts, :max_artifacts, 16)

    if is_integer(retention_ms) and retention_ms > 0 and is_integer(max_artifacts) and
         max_artifacts > 0 do
      {:ok, %{viewers: viewers, retention_ms: retention_ms, max: max_artifacts, artifacts: %{}}}
    else
      {:stop, :invalid_artifact_options}
    end
  end

  @impl true
  def handle_call({:publish, entrypoint, files}, _from, state) when is_map(files) do
    with :ok <- validate_bundle(entrypoint, Map.keys(files)),
         :ok <- validate_bytes(files) do
      now = System.monotonic_time(:millisecond)
      artifacts = Map.reject(state.artifacts, fn {_, value} -> value.expires_at <= now end)
      state = %{state | artifacts: artifacts}

      if map_size(artifacts) < state.max do
        id = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

        revision =
          files
          |> Enum.sort()
          |> then(&:erlang.term_to_binary({entrypoint, &1}))
          |> Tree.revision()

        reference = %{
          id: id,
          revision: revision,
          entrypoint: entrypoint,
          media_type: media_type(entrypoint)
        }

        stored = %{reference: reference, files: files, expires_at: now + state.retention_ms}
        {:reply, {:ok, reference}, put_in(state.artifacts[id], stored)}
      else
        {:reply, {:error, :artifact_capacity}, state}
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:publish, _, _}, _from, state),
    do: {:reply, {:error, :invalid_artifact_bundle}, state}

  def handle_call({:read, viewer, id, path}, _from, state) do
    now = System.monotonic_time(:millisecond)

    result =
      with true <- MapSet.member?(state.viewers, viewer),
           %{expires_at: expires_at} = artifact when expires_at > now <- state.artifacts[id],
           path = path || artifact.reference.entrypoint,
           {:ok, bytes} <- Map.fetch(artifact.files, path) do
        {:ok, %{content: bytes, headers: headers(path)}}
      else
        _ -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  def handle_call({:revoke, id}, _from, state),
    do: {:reply, :ok, %{state | artifacts: Map.delete(state.artifacts, id)}}

  defp validate_bundle(entrypoint, paths)
       when is_list(paths) and length(paths) in 1..@max_files do
    if entrypoint in paths and media_type(entrypoint) == @media_types[".html"] and
         Enum.uniq(paths) == paths and Enum.all?(paths, &valid_asset?/1) do
      :ok
    else
      {:error, :invalid_artifact_bundle}
    end
  end

  defp validate_bundle(_, _), do: {:error, :invalid_artifact_bundle}

  defp valid_asset?(path) do
    FilePath.validate(path) == :ok and byte_size(path) <= 1024 and
      Regex.match?(~r/\A[a-zA-Z0-9_.\/-]+\z/, path) and not is_nil(media_type(path))
  end

  defp media_type(path) when is_binary(path) do
    if String.valid?(path), do: @media_types[Path.extname(path)]
  end

  defp media_type(_), do: nil

  defp validate_bytes(files) do
    if Enum.all?(files, fn {_, bytes} -> is_binary(bytes) and String.valid?(bytes) end) do
      if Enum.sum_by(files, fn {_, bytes} -> byte_size(bytes) end) <= @max_bytes,
        do: :ok,
        else: {:error, :artifact_too_large}
    else
      {:error, :invalid_artifact_bundle}
    end
  end

  defp headers(path) do
    %{
      "content-type" => media_type(path),
      "content-security-policy" =>
        "sandbox allow-scripts; default-src 'none'; script-src 'self'; style-src 'self'; base-uri 'none'; form-action 'none'",
      "x-content-type-options" => "nosniff",
      "referrer-policy" => "no-referrer",
      "cache-control" => "private, no-store"
    }
  end
end
