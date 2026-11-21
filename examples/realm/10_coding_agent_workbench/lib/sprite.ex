defmodule RealmWorkbench.Sprite do
  @behaviour Jido.Realm.FileBackend
  alias RealmWorkbench.{Provider, Runs}
  alias Sprites.Filesystem

  def connect(root) do
    name = System.get_env("WORKBENCH_SPRITE")
    token = System.get_env("SPRITES_TEST_TOKEN") || System.get_env("SPRITES_TOKEN")

    cond do
      name in [nil, ""] ->
        {:error, "Set WORKBENCH_SPRITE to a test Sprite."}

      token in [nil, ""] ->
        {:ok, {:cli, name, root}}

      true ->
        sprite = Sprites.sprite(Sprites.new(token), name)
        {:ok, {:sdk, sprite, Filesystem.new(sprite, root), root}}
    end
  end

  def mkdir_root({:sdk, sprite, _, _}, root) do
    case Sprites.cmd(sprite, "mkdir", ["-p", "--", root], timeout: 20_000) do
      {_, 0} -> :ok
      _ -> {:error, :backend_error}
    end
  end

  def mkdir_root({:cli, name, _}, root), do: cli_result(name, ["mkdir", "-p", "--", root])

  @impl true
  def run({:sdk, _, fs, _}, :read, path, _), do: normalize_read(Filesystem.read(fs, path))
  def run({:sdk, _, fs, _}, :mkdir, path, _), do: normalize(Filesystem.mkdir_p(fs, path))

  def run({:sdk, _, fs, _}, op, path, bytes) when op in [:create, :edit] do
    with :ok <- check_existing(Filesystem.stat(fs, path), op),
         do: normalize(Filesystem.write(fs, path, bytes))
  end

  def run({:cli, name, root}, :read, path, _) do
    case cli(name, [
           "sh",
           "-c",
           ~S([ -f "$1" ] || exit 4; cat -- "$1"),
           "realm-file",
           root <> "/" <> path
         ]) do
      {bytes, 0} -> {:ok, bytes}
      {_, 4} -> {:error, :not_found}
      _ -> {:error, :backend_error}
    end
  end

  def run({:cli, name, root}, :mkdir, path, _),
    do: cli_result(name, ["mkdir", "-p", "--", root <> "/" <> path])

  def run({:cli, name, root}, op, path, bytes) when op in [:create, :edit] do
    guard =
      case op do
        :create -> ~S([ ! -e "$1" ] || exit 5; set -C; )
        :edit -> ~S([ -f "$1" ] || exit 4; )
      end

    command = guard <> ~S|printf '%s' "$2" | <> " | " <> ~S|base64 -d > "$1"|

    cli_result(name, [
      "sh",
      "-c",
      command,
      "realm-file",
      root <> "/" <> path,
      Base.encode64(bytes)
    ])
  end

  def run(_, _, _, _), do: {:error, :unsupported_file_operation}

  defp check_existing({:error, :enoent}, :create), do: :ok
  defp check_existing({:error, :enoent}, :edit), do: {:error, :not_found}
  defp check_existing({:ok, _}, :create), do: {:error, :already_exists}
  defp check_existing({:ok, %{"isDir" => false}}, :edit), do: :ok
  defp check_existing(_, _), do: {:error, :backend_error}

  defp normalize_read({:ok, bytes}), do: {:ok, bytes}
  defp normalize_read({:error, :enoent}), do: {:error, :not_found}
  defp normalize_read(_), do: {:error, :backend_error}
  defp normalize(:ok), do: :ok
  defp normalize(_), do: {:error, :backend_error}

  defp cli_result(name, args) do
    case cli(name, args) do
      {_, 0} -> :ok
      {_, 4} -> {:error, :not_found}
      {_, 5} -> {:error, :already_exists}
      _ -> {:error, :backend_error}
    end
  end

  defp cli(name, args) do
    System.cmd("sprite", command(name, args),
      stderr_to_stdout: false,
      env: [{"UPGRADE_CHECK", "false"}]
    )
  end

  defp command(name, args),
    do: ["-s", name, "exec", "--no-stdin", "--no-port-forward", "--" | args]

  def start({:cli, name, root}, job, port, script) do
    shell =
      ~S(cd "$1" || exit 1; export PORT="$2" BIND_IP=127.0.0.1; shift 2; exec timeout 3600 sh -c "$1")

    args = ["sh", "-c", shell, "realm-preview", root, Integer.to_string(port), script]

    with {:ok, pid} <- Provider.exec(["sprite" | command(name, args)], job) do
      case proxy(name, job, port) do
        {:ok, proxy} ->
          {:ok, %{pid: pid, proxy: proxy}}

        {:error, _} = error ->
          :exec.stop(pid)
          error
      end
    end
  end

  def start({:sdk, sprite, _, root}, job, port, script) do
    owner = spawn(fn -> stream(job.id) end)
    options = [dir: root, owner: owner, env: [{"PORT", "#{port}"}, {"BIND_IP", "127.0.0.1"}]]

    with {:ok, command} <- Sprites.spawn(sprite, "timeout", ["3600", "sh", "-c", script], options) do
      case proxy(sprite.name, job, port) do
        {:ok, proxy} ->
          {:ok, %{command: command, proxy: proxy}}

        {:error, reason} ->
          RealmWorkbench.Sprite.stop_command(command)
          {:error, reason}
      end
    else
      {:error, _} = error ->
        Process.exit(owner, :shutdown)
        error
    end
  end

  def stop_command(%{pid: pid}), do: if(Process.alive?(pid), do: GenServer.stop(pid))

  def stop_proxy(pid), do: if(Process.alive?(pid), do: :exec.stop(pid))

  # Sprites 0.2.4 does not dispatch accepted sockets to its proxy server.
  defp proxy(name, job, port),
    do: Provider.exec(["sprite", "-s", name, "proxy", "#{port}:#{port}"], job)

  defp stream(id) do
    receive do
      {label, _, bytes} when label in [:stdout, :stderr] ->
        Runs.log(id, String.replace_invalid(bytes))
        stream(id)

      {label, _, _} when label in [:exit, :error] ->
        :ok
    after
      86_400_000 -> :ok
    end
  end
end
