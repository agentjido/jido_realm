defmodule Jido.Realm.Runner.AppleContainer do
  @moduledoc """
  Runs programs and services from an owned Realm snapshot in Apple Container.
  The host selects the cached arm64 Linux image, source paths, and runtime.
  """

  @behaviour Jido.Realm.Runner
  @behaviour Jido.Realm.Preview

  alias Jido.Realm.Runner.{CLI, Staged}

  @metadata_limit 524_288

  @impl Jido.Realm.Runner
  def prepare(runtime, lease, opts), do: Staged.prepare(__MODULE__, runtime, lease, opts)

  @impl Jido.Realm.Preview
  def prepare(lease, opts), do: Staged.prepare_service(__MODULE__, lease, opts)

  @impl Jido.Realm.Runner
  defdelegate controls(config), to: Staged

  @impl Jido.Realm.Runner
  defdelegate execute(config, request, grants), to: Staged

  @impl Jido.Realm.Preview
  defdelegate start(config, request), to: Staged

  @impl Jido.Realm.Preview
  defdelegate stop(config, handle), to: Staged

  @impl Jido.Realm.Preview
  defdelegate running?(handle), to: Staged

  @impl Jido.Realm.Preview
  def verified_source?(_), do: true

  @doc false
  defdelegate reconcile(config, request), to: Staged

  @doc false
  def connect(_) do
    case System.find_executable("container") do
      cli when is_binary(cli) -> {:ok, cli}
      _ -> {:error, :runtime_unavailable}
    end
  end

  @doc false
  def image_identity(cli, image) do
    with {0, output} <- metadata(cli, ["image", "inspect", image]),
         {:ok, [%{"id" => id, "variants" => variants}]} <- JSON.decode(output),
         true <-
           Enum.any?(variants, fn variant ->
             match?(%{"architecture" => "arm64", "os" => "linux"}, variant["platform"]) and
               get_in(variant, ["config", "config", "Volumes"]) == nil
           end) do
      {:ok, id}
    else
      _ -> {:error, :image_unavailable}
    end
  end

  @doc false
  def create(cli, args, timeout, watch), do: command(cli, ["create" | args], timeout, watch)

  @doc false
  def boot(cli, name), do: command(cli, ["start", name])

  @doc false
  def attach(cli, name, timeout, watch, on_output \\ nil),
    do: command(cli, ["start", "--attach", name], timeout, watch, on_output)

  @doc false
  def remove(cli, name) do
    case command(cli, ["delete", "--force", name]) do
      {0, _} ->
        :ok

      _ ->
        {:error, :unknown}
    end
  end

  @doc false
  def absent?(cli, name) do
    case containers(cli, ["list", "--all", "--format", "json"], name) do
      {:ok, listed?} -> not listed?
      _ -> false
    end
  end

  @doc false
  def running?(cli, name), do: containers(cli, ["list", "--format", "json"], name) == {:ok, true}

  defp containers(cli, args, name) do
    with {0, output} <- metadata(cli, args),
         {:ok, rows} when is_list(rows) <- JSON.decode(output) do
      {:ok, Enum.any?(rows, &(get_in(&1, ["configuration", "id"]) == name))}
    end
  end

  @doc false
  def logs(cli, name) do
    {_, output} = command(cli, ["logs", name])
    String.replace_invalid(output, "?")
  end

  @doc false
  def host_port(_) do
    with {:ok, listener} <- :gen_tcp.listen(0, ip: {127, 0, 0, 1}),
         {:ok, port} <- :inet.port(listener),
         :ok <- :gen_tcp.close(listener) do
      {:ok, port}
    end
  end

  @doc false
  def published_port(_, _, _, host_port), do: {:ok, host_port}

  @doc false
  def preview_network(_), do: :ok

  @doc false
  def mount_options, do: ""

  @doc false
  def run_flags, do: ["--network", "none", "--no-dns"]

  @doc false
  def preview_flags(_, host_port, port),
    do: ["--publish", "127.0.0.1:#{host_port}:#{port}", "--env", "PORT=#{port}"]

  @doc false
  def staged_flags, do: ["--tmpfs", "/tmp", "--platform", "linux/arm64"]

  @doc false
  def pinned_image(image, _identity), do: image

  defp metadata(cli, args), do: CLI.run(cli, args, 8_000, nil, limit: @metadata_limit)

  defp command(cli, args, timeout \\ 8_000, watch \\ nil, on_output \\ nil),
    do: CLI.run(cli, args, timeout, watch, on_output: on_output)
end
