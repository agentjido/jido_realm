defmodule Jido.Realm.Coding do
  @moduledoc """
  Opt-in actions for coding in a Realm. Register only the actions the selected
  Realm supports. Reads and file operations work with Local and Memory.
  Guest commands require a managed session with a coding runner.
  """

  alias Jido.Realm
  alias Jido.Realm.{FilePath, Runner}

  @max_entries 512
  @max_display 8192

  @doc "Returns the file actions available to a coding agent."
  def file_actions do
    [__MODULE__.Glob, __MODULE__.Grep, __MODULE__.Read, __MODULE__.Write, __MODULE__.Edit]
  end

  @doc "Returns the optional guest command actions."
  def guest_actions, do: [__MODULE__.Bash, __MODULE__.RunCheck]

  @doc false
  def paths(read, roots) do
    walk(read, Enum.map(roots, &%{path: &1, type: :directory}), [], @max_entries)
  end

  defp walk(_, [], found, _), do: {:ok, Enum.reverse(found), false}
  defp walk(_, _, found, 0), do: {:ok, Enum.reverse(found), true}

  defp walk(read, [%{type: :directory, path: path} | rest], found, remaining) do
    with {:ok, %{entries: entries}} <- read.(:list, path) do
      walk(read, Enum.take(entries, remaining + 1) ++ rest, found, remaining - 1)
    end
  end

  defp walk(read, [%{type: :file, path: path} | rest], found, remaining),
    do: walk(read, rest, [path | found], remaining - 1)

  @doc false
  def glob(context, params) do
    pattern = params.pattern

    with true <- byte_size(pattern) in 1..256,
         true <- Enum.all?(String.split(pattern, "/"), &(FilePath.validate(&1) == :ok)),
         {:ok, files, partial} <- paths(reader(context, params), [params[:path] || "."]) do
      regex =
        pattern
        |> Regex.escape()
        |> String.replace("\\*\\*/", "(?:.*/)?")
        |> String.replace("\\*\\*", ".*")
        |> String.replace("\\*", "[^/]*")
        |> String.replace("\\?", "[^/]")
        |> then(&Regex.compile!("^" <> &1 <> "$", "u"))

      scope = params[:path] || "."
      matches = Enum.filter(files, &Regex.match?(regex, relative(scope, &1)))
      limit = params[:limit] || 50
      {:ok, %{paths: Enum.take(matches, limit), truncated: partial or length(matches) > limit}}
    else
      false -> {:error, :invalid_pattern}
      error -> error
    end
  end

  defp relative(".", path), do: path
  defp relative(scope, path), do: String.replace_prefix(path, scope <> "/", "")

  @doc false
  def grep(context, params) do
    if params[:native] do
      Realm.coding_run(context, params[:realm], :grep, params)
    else
      if params[:regex], do: {:error, :regex_unavailable}, else: literal_grep(context, params)
    end
  end

  defp literal_grep(context, params) do
    read = reader(context, params)
    limit = params[:limit] || 30

    with {:ok, files, partial} <- paths(read, [params[:path] || "."]) do
      {matches, skipped} =
        Enum.reduce_while(files, {[], false}, fn path, {matches, skipped} ->
          if length(matches) > limit do
            {:halt, {matches, skipped}}
          else
            case read.(:read_coding, path) do
              {:ok, %{content: bytes}} ->
                lines =
                  bytes
                  |> String.splitter("\n")
                  |> Stream.with_index(1)
                  |> Stream.filter(fn {line, _} -> String.contains?(line, params.query) end)
                  |> Stream.map(fn {line, number} ->
                    %{path: path, line: number, text: display(line, 512)}
                  end)
                  |> Enum.take(limit + 1 - length(matches))

                {:cont, {matches ++ lines, skipped}}

              {:error, _} ->
                {:cont, {matches, true}}
            end
          end
        end)

      {:ok,
       %{
         matches: Enum.take(matches, limit),
         truncated: partial or skipped or length(matches) > limit
       }}
    end
  end

  @doc false
  def read(context, params) do
    read = reader(context, params)

    case {params[:path], params[:paths]} do
      {path, nil} when is_binary(path) ->
        read_one(read, path, params)

      {nil, [_ | _] = paths} ->
        {:ok,
         %{
           files:
             Enum.map(paths, fn path ->
               case read_one(read, path, params) do
                 {:ok, result} -> result
                 {:error, reason} -> %{path: path, error: reason}
               end
             end)
         }}

      _ ->
        {:error, :invalid_read_paths}
    end
  end

  defp read_one(read, path, params) do
    first = params[:start_line] || 1
    count = params[:line_count] || 200

    with {:ok, result} <- read.(:read_coding, path) do
      lines =
        result.content
        |> String.splitter("\n")
        |> Stream.drop(first - 1)
        |> Enum.take(count + 1)

      bytes = lines |> Enum.take(count) |> Enum.join("\n")

      {:ok,
       %{
         path: path,
         revision: result.revision,
         start_line: first,
         content: display(bytes, @max_display),
         truncated: length(lines) > count or byte_size(bytes) > @max_display
       }}
    end
  end

  @doc false
  def display(bytes, limit) do
    {clipped, _} = Runner.clip(bytes, limit)
    String.replace_invalid(clipped)
  end

  @doc false
  def result({:ok, _} = success, _path), do: success

  def result({:error, reason}, path) do
    {:error,
     Jido.Error.execution_error("Realm coding action failed: #{inspect(reason)}",
       details: %{path: path, reason: inspect(reason)}
     )}
  end

  defp reader(context, params),
    do: &Realm.file(context, params[:realm], &1, &2)
end
