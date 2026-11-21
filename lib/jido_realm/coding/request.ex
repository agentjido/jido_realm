defmodule Jido.Realm.Coding.Request do
  @moduledoc false

  alias Jido.Realm.{Coding, Runner}

  @limit 30_000

  def build(kind, params, id, checks) do
    with true <- is_binary(id) and byte_size(id) in 1..128,
         {:ok, request} <- options(kind, params, checks) do
      {:ok,
       Map.merge(%{id: id, kind: kind, runtime: :bash, args: [], timeout_ms: @limit}, request)}
    else
      false -> {:error, :invalid_request_id}
      error -> error
    end
  end

  def check_entrypoint(runtime, path, opts, name, id, source_ref) do
    with true <- valid_source?(source_ref),
         {:ok, request} <- Runner.request(runtime, path, opts) do
      {:ok, Map.merge(request, %{id: id, kind: :check, check: name, source_ref: source_ref})}
    else
      false -> {:error, :invalid_run_options}
      error -> error
    end
  end

  def control(:bash), do: :bash_command
  def control(:check), do: :checked_source
  def control(:grep), do: :native_grep

  defp options(:bash, %{command: command} = params, _) do
    cwd = params[:cwd] || "."
    timeout = params[:timeout_ms] || @limit

    with :ok <- directory(cwd),
         true <- valid_command?(command) and is_integer(timeout) and timeout in 1..@limit do
      {:ok, %{command: command, cwd: cwd, timeout_ms: timeout}}
    else
      false -> {:error, :invalid_run_options}
      error -> error
    end
  end

  defp options(:check, %{name: name} = params, checks) do
    with {:ok, %{command: command} = check} <- Map.fetch(checks, name),
         cwd = Map.get(check, :cwd, "."),
         :ok <- directory(cwd),
         true <- valid_command?(command),
         reference = params[:source_ref],
         true <- valid_source?(reference) do
      {:ok,
       %{
         command: command,
         cwd: cwd,
         env: Map.get(check, :env, %{}),
         check: name,
         source_ref: reference
       }}
    else
      :error -> {:error, :unknown_check}
      false -> {:error, :invalid_run_options}
      error -> error
    end
  end

  defp options(:grep, %{query: query} = params, _) do
    cwd = params[:path] || "."
    limit = params[:limit] || 30

    with :ok <- directory(cwd),
         true <-
           is_binary(query) and byte_size(query) in 1..256 and
             String.valid?(query) and not String.contains?(query, <<0>>),
         true <- is_integer(limit) and limit in 1..100 do
      mode = if params[:regex], do: "--regexp", else: "--fixed-strings"
      args = [mode, query, Integer.to_string(limit + 1)]

      command = """
      if [[ "$1" == "--fixed-strings" ]]; then
        mode=--fixed-strings
      fi
      rg --no-config --hidden --no-ignore --color=never --json $mode -e "$2" -- . |
        awk -v limit="$3" '/^{"type":"match"/ { print; if (++seen >= limit) exit }'
      status=${PIPESTATUS[0]}
      if [[ "$status" == 1 || "$status" == 141 ]]; then exit 0; fi
      exit "$status"
      """

      {:ok, %{command: command, args: args, cwd: cwd, limit: limit}}
    else
      false -> {:error, :invalid_pattern}
      error -> error
    end
  end

  defp options(_, _, _), do: {:error, :invalid_run_options}

  defp directory("."), do: :ok
  defp directory(path), do: Runner.validate_path(path)

  defp valid_source?(source_ref),
    do: is_nil(source_ref) or (is_binary(source_ref) and byte_size(source_ref) <= 128)

  defp valid_command?(command),
    do:
      is_binary(command) and byte_size(command) in 1..8192 and String.valid?(command) and
        not String.contains?(command, <<0>>)

  def result(%{kind: :grep, limit: limit, cwd: cwd}, {:ok, result})
      when result.status in [:succeeded, :resource_limit] do
    matches =
      result.output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        case JSON.decode(line) do
          {:ok,
           %{
             "type" => "match",
             "data" => %{
               "path" => %{"text" => path},
               "line_number" => number,
               "lines" => %{"text" => text}
             }
           }} ->
            relative = Runner.rooted(cwd, String.replace_prefix(path, "./", ""))

            if Runner.validate_path(relative) == :ok,
              do: [
                %{
                  path: relative,
                  line: number,
                  text: Coding.display(String.trim_trailing(text, "\n"), 512)
                }
              ],
              else: []

          _ ->
            []
        end
      end)

    {:ok,
     %{
       id: result.id,
       matches: Enum.take(matches, limit),
       truncated: result.truncated or length(matches) > limit,
       source_ref: result.source_ref
     }}
  end

  def result(%{kind: :grep}, {:ok, %{status: :failed}}), do: {:error, :invalid_pattern}

  def result(%{kind: :check, check: name}, {:ok, result}),
    do: {:ok, Map.merge(result, %{check: name, check_id: result.id})}

  def result(_, result), do: result
end
