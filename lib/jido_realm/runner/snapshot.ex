defmodule Jido.Realm.Runner.Snapshot do
  @moduledoc false

  alias Jido.Realm.{Coding, Local, Runner, Tree}

  @max_bytes 4_194_304

  def capture(root, inputs, toolchain, stage) do
    read = &Local.captured_file(root, &1, &2)

    case Local.with_lock(root, fn -> collect(read, inputs, stage) end) do
      {:ok, revisions} ->
        source_ref =
          Tree.revision(:erlang.term_to_binary({toolchain, revisions}, [:deterministic]))

        {:ok, %{source_ref: source_ref, toolchain: toolchain, inputs: Map.new(revisions)}}

      {:error, _} = error ->
        error

      :aborted ->
        {:error, :snapshot_unavailable}
    end
  end

  defp collect(read, %{files: files, directories: dirs}, stage) do
    with {:ok, discovered, false} <- Coding.paths(read, dirs),
         :ok <- File.chmod(stage, 0o755) do
      (files ++ discovered)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reduce_while({:ok, [], 0}, &copy(read, stage, &1, &2))
      |> case do
        {:ok, revisions, _} -> {:ok, Enum.reverse(revisions)}
        error -> error
      end
    else
      {:ok, _, true} -> {:error, :input_limit}
      error -> error
    end
  end

  defp copy(read, stage, path, {:ok, revisions, size}) do
    target = Path.join(stage, path)

    with :ok <- Runner.validate_path(path),
         {:ok, %{content: bytes, revision: revision}} <- read.(:read_coding, path),
         total when total <= @max_bytes <- size + byte_size(bytes),
         :ok <- File.mkdir_p(Path.dirname(target)),
         :ok <- File.write(target, bytes, [:exclusive]) do
      {:cont, {:ok, [{path, revision} | revisions], total}}
    else
      {:error, _} = error -> {:halt, error}
      _ -> {:halt, {:error, :input_limit}}
    end
  end
end
