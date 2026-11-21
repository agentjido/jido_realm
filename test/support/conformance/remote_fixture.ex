defmodule Jido.Realm.Conformance.RemoteFixture do
  @moduledoc false
  @behaviour Jido.Realm.Conformance.Fixture
  @behaviour Jido.Realm.RemoteFiles

  alias Jido.Realm.{RemoteFiles, Session}

  @impl Jido.Realm.Conformance.Fixture
  def prepare(%{fixture_options: options}) do
    store = Keyword.fetch!(options, :store)
    prefix = Keyword.fetch!(options, :prefix)
    scope = %{store: store, prefix: prefix}

    client =
      ExUnit.Callbacks.start_supervised!(
        {Agent, fn -> %{trees: %{}, count: 0, commits: %{}, lost: nil, outcomes: %{}} end},
        id: make_ref()
      )

    %{
      runtime_options: session(client, scope, true),
      client: client,
      scope: scope,
      observe: fn path -> observe(client, store, Path.join(prefix, path)) end
    }
  end

  def session(client, scope, writable) do
    options = %{transport: {__MODULE__, client}, scope: scope, writable: writable}

    session =
      ExUnit.Callbacks.start_supervised!(
        {Session, provider: {RemoteFiles, options}},
        id: make_ref()
      )

    grants = if writable, do: :all, else: [:open, :close, :read]
    [session: session, grants: grants]
  end

  def observe(client, store, path) do
    Agent.get(client, fn state ->
      case get_in(state, [:trees, store, path]) do
        nil -> {:error, :not_found}
        %{content: bytes} -> {:ok, bytes}
      end
    end)
  end

  def advance(client, store, path, content) do
    Agent.get_and_update(client, fn state ->
      {result, state} = publish(state, store, path, content)
      {result, state}
    end)
  end

  def lose_reply(client, path), do: Agent.update(client, &%{&1 | lost: path})
  def count(client), do: Agent.get(client, & &1.count)
  def commit(client, repo, commit), do: Agent.get(client, &get_in(&1, [:commits, {repo, commit}]))

  @impl Jido.Realm.RemoteFiles
  def fetch(client, scope, path) do
    key = Path.join(scope.prefix, path)

    Agent.get(client, fn state ->
      case get_in(state, [:trees, scope.store, key]) do
        nil -> {:error, :not_found}
        entry -> {:ok, entry}
      end
    end)
  end

  @impl Jido.Realm.RemoteFiles
  def mutate(client, scope, path, request) do
    key = Path.join(scope.prefix, path)

    Agent.get_and_update(client, fn state ->
      current = get_in(state, [:trees, scope.store, key])

      case precondition(request.expected, current) do
        :ok ->
          {result, state} = publish(state, scope.store, key, request.content)
          state = put_in(state.outcomes[{scope, path, request.id}], %{outcome: :applied})

          if state.lost == path,
            do: {{:error, :unknown}, %{state | lost: nil}},
            else: {result, state}

        {:error, _} = error ->
          {error, state}
      end
    end)
  end

  @impl Jido.Realm.RemoteFiles
  def reconcile(client, scope, path, request_id) do
    Agent.get(client, fn state ->
      case Map.fetch(state.outcomes, {scope, path, request_id}) do
        {:ok, _} = result -> result
        :error -> {:error, :unknown}
      end
    end)
  end

  defp precondition(:absent, nil), do: :ok
  defp precondition(:absent, _), do: {:error, :already_exists}
  defp precondition({:matches, revision}, %{revision: revision}), do: :ok
  defp precondition({:matches, _}, _), do: {:error, :conflict}

  defp publish(state, store, key, content) do
    count = state.count + 1
    revision = Integer.to_string(count)
    tree = Map.get(state.trees, store, %{})

    tree =
      if is_nil(content),
        do: Map.delete(tree, key),
        else: Map.put(tree, key, %{revision: revision, content: content})

    state = %{state | count: count, trees: Map.put(state.trees, store, tree)}

    case store do
      {:github, repo, _branch} ->
        state = put_in(state.trees[{:github_commit, repo, revision}], tree)

        state =
          put_in(state.commits[{repo, revision}], %{store: store, path: key, content: content})

        {{:ok, %{commit: revision}}, state}

      {:s3, _bucket} ->
        {:ok, state}
    end
  end
end
