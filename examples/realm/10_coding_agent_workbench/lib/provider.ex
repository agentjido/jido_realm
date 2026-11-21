defmodule RealmWorkbench.Provider do
  @behaviour Jido.Realm.Provider
  alias Jido.Realm.Local
  alias RealmWorkbench.Runs

  @elixir "hexpm/elixir:1.20.4-erlang-29.1.2-debian-bookworm-20261027-slim"
  @node "node:22-alpine"
  @phoenix """
  set -eu
  export MIX_ENV=prod
  export ERL_FLAGS='+S 2:2'
  mix help hex.info >/dev/null 2>&1 || mix local.hex --force
  mix local.rebar --if-missing --force
  mix deps.get
  mix compile
  exec mix run --no-halt
  """
  @typescript "exec node --experimental-strip-types server.ts"

  @impl true
  def open(job) do
    with {:ok, binding} <- file_binding(job) do
      {:ok,
       %{
         binding: binding,
         placement: job.root,
         ownership: :borrowed,
         capabilities: %{files: true, tree: true}
       }}
    end
  end

  @impl true
  def close(_lease, _job), do: :ok

  defp file_binding(%{provider: "sprites"} = job) do
    with {:ok, target} <- RealmWorkbench.Sprite.connect(job.root),
         :ok <- RealmWorkbench.Sprite.mkdir_root(target, job.root) do
      {:ok, {RealmWorkbench.Sprite, target}}
    end
  end

  defp file_binding(job) do
    with :ok <- File.mkdir_p(job.root), do: {:ok, {Local, job.root}}
  end

  def launch(job) do
    with {:ok, port} <- free_port(),
         {:ok, app} <- start_app(job, port) do
      case probe(job, app, port) do
        :ok ->
          Runs.resource(job.id, app)
          {:ok, %{url: "http://127.0.0.1:#{port}/", port: port, http_status: 200}}

        {:error, reason} ->
          stop(app)
          {:error, reason}
      end
    end
  end

  defp start_app(%{provider: "local"} = job, port) do
    args =
      [
        "/usr/bin/env",
        "-i",
        "PATH=#{System.get_env("PATH")}",
        "HOME=#{System.user_home!()}",
        "LANG=en_US.UTF-8",
        "PORT=#{port}",
        "BIND_IP=127.0.0.1"
      ] ++
        for {var, value} <- System.get_env(),
            var in ~w(MIX_HOME MIX_ARCHIVES HEX_HOME),
            do: "#{var}=#{value}"

    with {:ok, pid} <- exec(args ++ ["/bin/sh", "-c", script(job)], job, job.root) do
      {:ok, %{pid: pid}}
    end
  end

  defp start_app(%{provider: provider} = job, port) when provider in ["docker", "apple"] do
    name = "jido-coding-" <> job.id
    image = if job.recipe == "phoenix", do: @elixir, else: @node
    mount = "type=bind,source=#{job.root},target=/workspace"

    args =
      engine_prefix(provider) ++
        [
          "run",
          "--rm",
          "--name",
          name,
          "--cpus",
          "2",
          "--memory",
          "768m",
          "--cap-drop",
          "ALL",
          "--mount",
          mount,
          "--workdir",
          "/workspace",
          "--env",
          "PORT=8080",
          "--env",
          "BIND_IP=0.0.0.0",
          "--publish",
          "127.0.0.1:#{port}:8080",
          "--entrypoint",
          "/bin/sh"
        ] ++
        if(provider == "docker",
          do: ["--pull=never", "--security-opt=no-new-privileges=true"],
          else: []
        ) ++
        [image, "-c", script(job)]

    with {:ok, pid} <- exec(args, job) do
      {:ok, %{pid: pid, provider: provider, name: name}}
    end
  end

  defp start_app(%{provider: "sprites"} = job, port) do
    with {:ok, target} <- RealmWorkbench.Sprite.connect(job.root),
         {:ok, app} <- RealmWorkbench.Sprite.start(target, job, port, script(job)) do
      {:ok, app}
    end
  end

  def stop(%{pid: pid} = app) do
    if Process.alive?(pid), do: :exec.stop(pid)
    cleanup_container(app)
    if proxy = app[:proxy], do: RealmWorkbench.Sprite.stop_proxy(proxy)
    :ok
  end

  def stop(%{command: command, proxy: proxy}) do
    RealmWorkbench.Sprite.stop_command(command)
    RealmWorkbench.Sprite.stop_proxy(proxy)
    :ok
  end

  defp cleanup_container(%{provider: provider, name: name}) do
    [executable | prefix] = engine_prefix(provider)
    args = if provider == "docker", do: ["rm", "--force", name], else: ["delete", "--force", name]
    System.cmd(executable, prefix ++ args, stderr_to_stdout: true)
  end

  defp cleanup_container(_), do: :ok

  defp engine_prefix("docker") do
    case System.get_env("JIDO_REALM_DOCKER_CONTEXT") do
      nil -> ["docker"]
      context -> ["docker", "--context", context]
    end
  end

  defp engine_prefix("apple"), do: ["container"]

  def exec([executable | args], job, directory \\ nil) do
    case System.find_executable(executable) do
      nil ->
        {:error, "#{executable} is unavailable"}

      path ->
        output = fn _, _, bytes -> Runs.log(job.id, String.replace_invalid(bytes)) end

        opts = [
          {:stdout, output},
          {:stderr, output},
          {:kill_timeout, 1},
          {:group, 0},
          :kill_group
        ]

        opts = if directory, do: [{:cd, directory} | opts], else: opts

        case :exec.run([path | args], opts, 5_000) do
          {:ok, pid, _} -> {:ok, pid}
          {:error, reason} -> {:error, "Could not start #{executable}: #{inspect(reason)}"}
        end
    end
  end

  defp script(%{recipe: "phoenix"}), do: @phoenix
  defp script(%{recipe: "typescript"}), do: @typescript

  defp free_port do
    with {:ok, socket} <- :gen_tcp.listen(0, ip: {127, 0, 0, 1}),
         {:ok, port} <- :inet.port(socket) do
      :gen_tcp.close(socket)
      {:ok, port}
    end
  end

  defp probe(job, app, port), do: probe(job, app, port, System.monotonic_time(:second) + 150)

  defp probe(job, app, port, deadline) do
    response =
      Req.get("http://127.0.0.1:#{port}/",
        retry: false,
        redirect: false,
        connect_options: [timeout: 1_000],
        receive_timeout: 1_000
      )

    case response do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        if body =~ "Hello, world!" and (job.recipe == "phoenix" or body =~ "Jido Realm"),
          do: :ok,
          else: {:error, "HTTP 200, but the page is missing the requested text"}

      _ ->
        if alive?(app) and System.monotonic_time(:second) < deadline do
          Process.sleep(350)
          probe(job, app, port, deadline)
        else
          {:error, "Preview did not pass its HTTP check.\n" <> Runs.log_tail(job.id)}
        end
    end
  end

  defp alive?(%{pid: pid}), do: Process.alive?(pid)
  defp alive?(%{command: %{pid: pid}}), do: Process.alive?(pid)
end
