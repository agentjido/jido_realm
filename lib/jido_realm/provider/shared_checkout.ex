defmodule Jido.Realm.Provider.SharedCheckout do
  @moduledoc """
  Gives a Realm a writable or read-only tree backed by a host Docker or gVisor
  profile. File calls and Bash runs share the same tree and provider lease.

  Set `:profile` to a `Jido.Realm.Host.Profile` name or configuration and
  `:bash` to the guest executable. Give the host handle only to trusted code.
  Keep other writers out of a host-owned checkout during the lease.

  Set `:check_files` to the complete list of source inputs for named checks.
  Those paths and the image identify the checked source. Build outputs can
  go to other paths. Set `:from` to restore a saved snapshot into a fresh tree.
  """

  @behaviour Jido.Realm.Provider
  @behaviour Jido.Realm.FileBackend
  @behaviour Jido.Realm.Runner

  alias Jido.Realm.{FilePath, Runner, Tree}
  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Error, Policy, Profile, SnapshotStore}

  @impl Jido.Realm.Provider
  def open(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, opts} <- Keyword.validate(opts, [:profile, :from, bash: "bash", check_files: []]),
         {:ok, profile} <- Keyword.fetch(opts, :profile),
         {:ok, %{provider: provider} = config} <- Profile.fetch(profile),
         true <- provider in [:docker, :gvisor],
         true <- valid_options?(opts),
         {:ok, workspace} <- Host.open(Keyword.take(opts, [:profile, :from])) do
      bind(workspace, opts, config)
    else
      {:error, %Error{} = error} -> realm_error(error)
      _ -> {:error, :invalid_workspace_binding}
    end
  end

  defp valid_options?(opts) do
    bash = opts[:bash]
    files = opts[:check_files]

    is_binary(bash) and byte_size(bash) in 1..1024 and not String.contains?(bash, <<0>>) and
      is_list(files) and length(files) <= 32 and Enum.all?(files, &(FilePath.validate(&1) == :ok))
  end

  defp bind(workspace, opts, profile) do
    case Host.info(workspace) do
      {:ok, info} ->
        handle = %{
          workspace: workspace,
          bash: opts[:bash],
          check_files: Enum.sort(Enum.uniq(opts[:check_files])),
          image: info.capabilities[:image],
          writable: Policy.allows?(info.policy, :write)
        }

        {:ok,
         %{
           binding: {__MODULE__, handle},
           placement: info.id,
           shared_tree: true,
           capabilities: %{
             files: Policy.allows?(info.policy, :read),
             tree: true,
             revisions: true,
             snapshots:
               Policy.allows?(info.policy, :save) and SnapshotStore.configured?(profile[:store])
           },
           runners:
             if(Policy.allows?(info.policy, :execute), do: %{bash: {__MODULE__, []}}, else: %{})
         }}

      {:error, error} ->
        with :ok <- Host.close(workspace), do: realm_error(error)
    end
  end

  @impl Jido.Realm.Provider
  def close(%{binding: {__MODULE__, %{workspace: workspace}}}, _opts) do
    workspace |> Host.close() |> normalize()
  end

  @impl Jido.Realm.Provider
  def save(%{binding: {__MODULE__, handle}}, nil), do: normalize(Host.save(handle.workspace))

  def save(%{binding: {__MODULE__, handle}}, verified_tree),
    do: normalize(Host.save(handle.workspace, verified_tree))

  @impl Jido.Realm.FileBackend
  def run(%{workspace: workspace}, operation, path, input) do
    case Host.realm_file(workspace, operation, path, input) do
      {:error, {:policy_denied, _}} -> {:error, :permission_denied}
      {:error, :quiescence_unknown} -> {:error, :unknown}
      result -> result
    end
  end

  @impl Jido.Realm.Runner
  def prepare(:bash, %{binding: {__MODULE__, handle}}, []), do: {:ok, handle}

  @impl Jido.Realm.Runner
  def controls(handle) do
    source = if handle.check_files == [], do: [], else: [:checked_source]
    access = if handle.writable, do: :writable_tree, else: :read_only_tree
    [:bash_command, :loopback_only, access | source]
  end

  @impl Jido.Realm.Runner
  def execute(handle, request, grants) do
    with :ok <- authorize_run(handle, grants),
         :ok <- supported_options(request),
         {:ok, source_ref} <- check_source(handle, request),
         {:ok, execution} <- run_command(handle, request),
         :ok <- expected_source(handle, source_ref),
         {:ok, evidence} <- check_evidence(handle, source_ref, execution) do
      result =
        Runner.result(
          status(execution),
          execution.exit_status,
          execution.output,
          execution.truncated
        )

      {:ok, Map.merge(result, evidence)}
    end
  end

  defp authorize_run(%{writable: true}, grants) do
    if Runner.allowed?(grants, :write), do: :ok, else: {:error, :permission_denied}
  end

  defp authorize_run(_, _), do: :ok

  defp supported_options(request) do
    if is_nil(request[:inputs]) and request[:env] in [nil, %{}],
      do: :ok,
      else: {:error, :unsupported_run_options}
  end

  defp run_command(handle, request) do
    args =
      case request do
        %{command: script, args: args} -> ["-c", script, "realm" | args]
        %{entrypoint: path, args: args} -> ["./" <> path | args]
      end

    handle.workspace
    |> Host.run([handle.bash | args],
      cwd: request.cwd,
      timeout_ms: request.timeout_ms,
      output_limit: Runner.output_limit()
    )
    |> normalize()
  end

  defp check_source(%{check_files: []}, %{kind: :check}), do: {:error, :unchecked_source}

  defp check_source(handle, %{kind: :check} = request) do
    with :ok <- check_entrypoint(handle, request),
         {:ok, revision} <- source_ref(handle),
         :ok <- compare_source(request[:source_ref], revision),
         do: {:ok, revision}
  end

  defp check_source(_, _), do: {:ok, nil}

  defp check_entrypoint(handle, %{cwd: cwd, entrypoint: path}) do
    if Runner.rooted(cwd, path) in handle.check_files,
      do: :ok,
      else: {:error, :unchecked_source}
  end

  defp check_entrypoint(_, _), do: :ok

  defp check_evidence(_, nil, _), do: {:ok, %{}}

  defp check_evidence(handle, ref, %{status: :exited, exit_status: 0}) do
    with {:ok, revision} <- normalize(Host.realm_revision(handle.workspace)) do
      {:ok, %{source_ref: ref, tree_revision: revision}}
    end
  end

  defp check_evidence(_, ref, _), do: {:ok, %{source_ref: ref}}

  defp expected_source(_, nil), do: :ok

  defp expected_source(handle, expected) do
    with {:ok, actual} <- source_ref(handle), do: compare_source(expected, actual)
  end

  defp compare_source(nil, _), do: :ok
  defp compare_source(expected, expected), do: :ok
  defp compare_source(_, _), do: {:error, :stale_source}

  defp source_ref(handle) do
    Enum.reduce_while(handle.check_files, {:ok, []}, fn path, {:ok, revisions} ->
      case run(handle, :read_coding, path, nil) do
        {:ok, %{revision: revision}} -> {:cont, {:ok, [{path, revision} | revisions]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, revisions} ->
        {:ok, Tree.revision(:erlang.term_to_binary({handle.image, handle.bash, revisions}))}

      error ->
        error
    end
  end

  defp status(%{status: :exited, exit_status: 0}), do: :succeeded
  defp status(%{status: :timed_out}), do: :timed_out
  defp status(_), do: :failed

  defp normalize({:error, %Error{} = error}), do: realm_error(error)
  defp normalize(result), do: result

  defp realm_error(%Error{code: code})
       when code in [:quiescence_unknown, :cleanup_unconfirmed, :closed, :open_timeout],
       do: {:error, :unknown}

  defp realm_error(%Error{code: :policy_denied}), do: {:error, :permission_denied}
  defp realm_error(%Error{code: :stale_file_view}), do: {:error, :stale_source}
  defp realm_error(%Error{code: code}), do: {:error, code}
end
