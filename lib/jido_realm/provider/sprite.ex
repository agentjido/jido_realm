defmodule Jido.Realm.Provider.Sprite do
  @moduledoc """
  Allocates or attaches a trusted Fly.io Sprite through the Elixir SDK.

  The host supplies a client, name, absolute root, and exact relative paths
  that the agent can read. Close deletes an owned Sprite and preserves a
  borrowed Sprite.
  """

  @behaviour Jido.Realm.Provider
  @behaviour Jido.Realm.FileBackend

  alias Jido.Realm.FilePath
  alias Sprites.Filesystem

  @max_bytes 1_048_576

  @impl Jido.Realm.Provider
  def open(%{
        mode: mode,
        client: %Sprites.Client{} = client,
        name: name,
        root: root,
        readable: paths
      })
      when mode in [:owned, :borrowed] and is_binary(name) and is_binary(root) and is_list(paths) do
    with true <- Regex.match?(~r/\A[a-z0-9][a-z0-9-]{0,62}\z/, name),
         true <- Path.type(root) == :absolute,
         true <- Enum.all?(paths, &(FilePath.validate(&1) == :ok)),
         {:ok, sprite} <- connect(mode, client, name) do
      {:ok,
       %{
         binding: {__MODULE__, {Sprites.filesystem(sprite, root), MapSet.new(paths)}},
         placement: name,
         capabilities: %{files: true},
         ownership: mode
       }}
    else
      false -> {:error, :invalid_sprite_binding}
      {:error, _} = error -> error
    end
  end

  def open(_), do: {:error, :invalid_sprite_binding}

  @impl Jido.Realm.Provider
  def close(%{ownership: :borrowed}, _), do: :ok

  def close(%{binding: {__MODULE__, {%Filesystem{sprite: sprite}, _}}}, _) do
    case Sprites.destroy(sprite) do
      :ok -> :ok
      {:error, _} -> {:error, :unknown}
    end
  end

  @impl Jido.Realm.FileBackend
  def run({fs, paths}, :read, path, _) do
    with true <- MapSet.member?(paths, path),
         {:ok, %{"isDir" => false, "size" => size}} when size in 0..@max_bytes <-
           Filesystem.stat(fs, path),
         {:ok, bytes} when is_binary(bytes) and byte_size(bytes) <= @max_bytes <-
           Filesystem.read(fs, path) do
      {:ok, bytes}
    else
      false -> {:error, :permission_denied}
      {:error, :enoent} -> {:error, :not_found}
      _ -> {:error, :backend_error}
    end
  end

  def run(_, _, _, _), do: {:error, :unsupported_file_operation}

  defp connect(:borrowed, client, name) do
    case Sprites.get_sprite(client, name) do
      {:ok, _} -> {:ok, Sprites.sprite(client, name)}
      {:error, {:not_found, _}} -> {:error, :not_found}
      {:error, _} -> {:error, :sprite_unavailable}
    end
  end

  defp connect(:owned, client, name) do
    case Sprites.create(client, name) do
      {:ok, sprite} -> {:ok, sprite}
      {:error, {:api_error, 409, _}} -> {:error, :already_exists}
      {:error, {:api_error, status, _}} when status in 400..499 -> {:error, :sprite_unavailable}
      {:error, _} -> {:error, :unknown}
    end
  end
end
