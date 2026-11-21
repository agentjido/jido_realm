defmodule Jido.Realm.RemoteFiles do
  @moduledoc """
  A borrowed file placement addressed by a transport and a host-selected scope.

  The transport applies mutation preconditions at the store. It returns
  `{:error, :unknown}` when it cannot establish whether a request took effect.
  A transport that supports reconciliation can look up the same request without
  repeating the mutation. Scope stays fixed for the life of the placement.
  """

  @behaviour Jido.Realm.Provider
  @behaviour Jido.Realm.FileBackend

  @callback fetch(client :: term(), scope :: term(), path :: String.t()) ::
              {:ok, %{content: binary(), revision: String.t()}} | {:error, atom()}
  @callback mutate(client :: term(), scope :: term(), path :: String.t(), request :: map()) ::
              :ok | {:ok, %{commit: String.t()}} | {:error, atom()}
  @callback reconcile(
              client :: term(),
              scope :: term(),
              path :: String.t(),
              request_id :: String.t()
            ) ::
              {:ok, %{outcome: :applied | :rejected}} | {:error, atom()}
  @optional_callbacks reconcile: 4

  @impl Jido.Realm.Provider
  def open(%{transport: {module, _}, scope: scope} = options) do
    reconcilable = Code.ensure_loaded?(module) and function_exported?(module, :reconcile, 4)

    {:ok,
     %{
       binding: {__MODULE__, options},
       placement: scope,
       ownership: :borrowed,
       capabilities: %{files: true, revisions: true, reconcile: reconcilable}
     }}
  end

  @impl Jido.Realm.Provider
  def close(_lease, _options), do: :ok

  @impl Jido.Realm.FileBackend
  def run(options, :read, path, _) do
    with {:ok, %{content: content}} <- fetch(options, path), do: {:ok, content}
  end

  def run(options, :read_revision, path, _), do: fetch(options, path)

  def run(%{transport: {module, client}, scope: scope}, :reconcile, path, request_id),
    do: module.reconcile(client, scope, path, request_id)

  def run(%{writable: true} = options, :create, path, content),
    do: mutate(options, path, :create, :absent, content)

  def run(%{writable: true} = options, :edit_revision, path, {revision, content}),
    do: mutate(options, path, :edit, {:matches, revision}, content)

  def run(%{writable: true} = options, :delete_revision, path, revision),
    do: mutate(options, path, :delete, {:matches, revision}, nil)

  def run(%{writable: true} = options, operation, path, content)
      when operation in [:edit, :delete] do
    with {:ok, %{revision: revision}} <- fetch(options, path),
         do: mutate(options, path, operation, {:matches, revision}, content)
  end

  def run(_, operation, _, _)
      when operation in [:create, :edit, :delete, :edit_revision, :delete_revision],
      do: {:error, :permission_denied}

  def run(_, _, _, _), do: {:error, :unsupported_file_operation}

  defp fetch(%{transport: {module, client}, scope: scope}, path),
    do: module.fetch(client, scope, path)

  defp mutate(%{transport: {module, client}, scope: scope}, path, operation, expected, content) do
    request_id = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    request = %{id: request_id, operation: operation, expected: expected, content: content}

    case module.mutate(client, scope, path, request) do
      {:error, :unknown} -> {:error, {:unknown, request_id}}
      result -> result
    end
  end
end
