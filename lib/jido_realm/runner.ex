defmodule Jido.Realm.Runner do
  @moduledoc """
  Execution adapter for an opened placement.

  The host selects the adapter and its options. Prepare checks the actual
  lease before Realm advertises the runtime. Execute receives validated paths,
  literal arguments, host grants, and a deadline. A terminal result confirms
  that execution has stopped. Return an unknown outcome if the adapter
  cannot confirm that state. A runner that reports `:bounded_progress` calls
  the optional `:on_output` function with each retained chunk and its
  truncation flag. Use `:resource_id` as the provider name when supplied.
  The public request ID can contain caller-supplied characters.
  """

  alias Jido.Realm.{FilePath, Files}

  @type request :: %{
          required(:id) => String.t(),
          required(:runtime) => atom(),
          required(:entrypoint) => String.t(),
          required(:cwd) => String.t(),
          required(:args) => [String.t()],
          required(:inputs) => [String.t()] | nil,
          required(:timeout_ms) => pos_integer(),
          optional(:resource_id) => String.t(),
          optional(:outputs) => [String.t()],
          optional(:on_output) => (binary(), boolean() -> any())
        }
  @type result :: %{
          required(:status) =>
            :succeeded
            | :failed
            | :timed_out
            | :resource_limit
            | :publication_failed
            | :test_failed
            | :setup_failed,
          required(:exit_code) => non_neg_integer() | nil,
          required(:output) => String.t(),
          required(:truncated) => boolean(),
          required(:published) => [String.t()],
          optional(:publication_error) => term()
        }

  @callback prepare(atom(), Jido.Realm.Provider.lease(), term()) ::
              {:ok, term()} | {:error, term()}
  @callback execute(term(), request(), :all | [atom()]) ::
              {:ok, result()} | {:error, term()}
  @doc "Returns the controls the adapter enforces for every run with this prepared state."
  @callback controls(term()) :: [atom()]
  @optional_callbacks controls: 1

  @runtime_names ~w(lua bash python javascript wasm)a
  @runtimes Map.new(@runtime_names, &{Atom.to_string(&1), &1})
  @default_timeout 2_000
  @max_timeout 20_000
  @output_limit 16_384

  @doc false
  def runtimes, do: @runtime_names

  @doc false
  def preview_request(runtime, entrypoint, opts) when runtime in [:native, "native"],
    do: request_for({:ok, :native}, entrypoint, opts)

  def preview_request(runtime, entrypoint, opts), do: request(runtime, entrypoint, opts)

  @doc false
  def request(runtime, entrypoint, opts), do: request_for(runtime(runtime), entrypoint, opts)

  defp request_for(runtime, entrypoint, opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, runtime} <- runtime,
         {:ok, opts} <-
           Keyword.validate(opts,
             cwd: ".",
             args: [],
             inputs: nil,
             outputs: [],
             timeout_ms: @default_timeout
           ),
         :ok <- validate_cwd(opts[:cwd]),
         :ok <- validate_path(entrypoint),
         true <- valid_args?(opts[:args]),
         true <- valid_inputs?(opts[:inputs]),
         true <- valid_outputs?(opts[:outputs]),
         timeout when is_integer(timeout) and timeout in 1..@max_timeout <- opts[:timeout_ms] do
      {:ok,
       maybe_outputs(
         %{
           id: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
           runtime: runtime,
           entrypoint: entrypoint,
           cwd: opts[:cwd],
           args: opts[:args],
           inputs: opts[:inputs],
           timeout_ms: timeout
         },
         opts[:outputs]
       )}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_run_options}
    end
  end

  defp request_for(_, _, _), do: {:error, :invalid_run_options}

  defp maybe_outputs(request, []), do: request
  defp maybe_outputs(request, outputs), do: Map.put(request, :outputs, outputs)

  defp runtime(value) when value in @runtime_names, do: {:ok, value}
  defp runtime(value) when is_map_key(@runtimes, value), do: Map.fetch(@runtimes, value)
  defp runtime(_), do: {:error, :unsupported_runtime}

  @doc false
  def prepare(lease, configurations, required_controls) do
    # Execution capabilities come from the prepared adapters for this lease.
    report = Map.drop(lease.capabilities, @runtime_names)

    runners =
      for {runtime, {module, options}} <- configurations,
          runtime in @runtime_names,
          {:ok, state} <- [module.prepare(runtime, lease, options)],
          provides_controls?(module, state, Map.get(required_controls, runtime, [])),
          into: %{} do
        {runtime, {module, state}}
      end

    %{
      lease
      | capabilities: Map.merge(report, Map.new(runners, fn {runtime, _} -> {runtime, true} end))
    }
    |> Map.put(:runners, runners)
  end

  def provides_controls?(_module, _state, []), do: true

  def provides_controls?(module, state, required) do
    with true <- function_exported?(module, :controls, 1),
         provided when is_list(provided) <- module.controls(state) do
      Enum.all?(required, &(&1 in provided))
    else
      _ -> false
    end
  end

  @doc false
  def reports_progress?({module, state}),
    do: provides_controls?(module, state, [:bounded_progress])

  @doc false
  def execute({module, state}, request, grants) do
    with :ok <- admit_outputs({module, state}, request, grants),
         {:ok, %{output: output, truncated: truncated} = result} <-
           module.execute(state, request, grants) do
      {output, clipped} = clip(output, @output_limit)

      {:ok,
       %{result | output: String.replace_invalid(output, "?"), truncated: truncated or clipped}}
    end
  end

  defp admit_outputs({module, state}, %{outputs: [_ | _]}, grants) do
    cond do
      not allowed?(grants, :write) ->
        {:error, :permission_denied}

      not provides_controls?(module, state, [:declared_outputs]) ->
        {:error, :unsupported_run_outputs}

      true ->
        :ok
    end
  end

  defp admit_outputs(_, _, _), do: :ok

  @doc false
  def result(status, exit_code, output \\ "", truncated \\ false) do
    %{status: status, exit_code: exit_code, output: output, truncated: truncated, published: []}
  end

  @doc false
  def revision(binding, path) do
    case Files.execute(binding, :read_revision, path, nil) do
      {:ok, %{revision: revision}} -> {:ok, revision}
      {:error, :not_found} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  @doc false
  def publish(drafts, binding, result) do
    drafts
    |> Enum.sort()
    |> Enum.reduce_while(result, fn {path, {bytes, revision}}, current ->
      {operation, input} =
        if revision, do: {:edit_revision, {revision, bytes}}, else: {:create, bytes}

      case Files.execute(binding, operation, path, input) do
        {:ok, _} -> {:cont, %{current | published: [path | current.published]}}
        {:error, reason} -> {:halt, publication_failed(current, path, reason)}
      end
    end)
    |> Map.update!(:published, &Enum.reverse/1)
  end

  @doc false
  def publication_failed(result, path, reason) do
    Map.merge(result, %{
      status: :publication_failed,
      publication_error: %{path: path, reason: reason}
    })
  end

  @doc false
  def output_limit, do: @output_limit

  @doc false
  def clip(bytes, limit) when byte_size(bytes) <= limit, do: {bytes, false}
  def clip(bytes, limit), do: {:binary.copy(binary_part(bytes, 0, limit)), true}

  @doc false
  def rooted(".", path), do: path
  def rooted(cwd, path), do: cwd <> "/" <> path

  @doc false
  def validate_path(path) when is_binary(path) and byte_size(path) <= 1_024,
    do: FilePath.validate(path)

  def validate_path(_), do: {:error, :invalid_path}

  @doc false
  def allowed?(:all, _), do: true
  def allowed?(grants, grant), do: grant in grants

  defp validate_cwd("."), do: :ok
  defp validate_cwd(path), do: validate_path(path)

  defp valid_inputs?(nil), do: true

  defp valid_inputs?(paths) when is_list(paths) and length(paths) <= 32,
    do: Enum.all?(paths, &(validate_path(&1) == :ok))

  defp valid_inputs?(_), do: false

  defp valid_outputs?(paths) when is_list(paths),
    do: valid_inputs?(paths) and Enum.uniq(paths) == paths

  defp valid_outputs?(_), do: false

  defp valid_args?(args) when is_list(args) and length(args) <= 32 do
    Enum.all?(args, fn arg ->
      is_binary(arg) and byte_size(arg) <= 2_048 and String.valid?(arg) and
        not String.contains?(arg, <<0>>)
    end)
  end

  defp valid_args?(_), do: false
end
