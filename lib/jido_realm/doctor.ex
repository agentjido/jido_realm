defmodule Jido.Realm.Doctor do
  @moduledoc false

  @lanes ~w(core native docker browser apple_container sprites live_sprite lmstudio)a
  @chrome "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  @docker_images [
    bash_image: {"JIDO_REALM_BASH_IMAGE", "bash:5.2"},
    python_image: {"JIDO_REALM_PYTHON_IMAGE", "python:3.13-alpine"},
    javascript_image: {"JIDO_REALM_JAVASCRIPT_IMAGE", "node:22-alpine"}
  ]
  @command_timeout 3_000

  def lanes, do: @lanes

  def report(lanes) do
    host = %{
      os: elem(:os.type(), 1),
      architecture: List.to_string(:erlang.system_info(:system_architecture)),
      elixir: System.version(),
      otp: List.to_string(:erlang.system_info(:otp_release))
    }

    %{host: host, lanes: Enum.map(lanes, &report_lane(&1, host))}
  end

  defp report_lane(lane, host) do
    checks = checks(lane, host)
    status = if Enum.all?(checks, &(&1.status == :ok)), do: :ready, else: :attention
    %{name: lane, status: status, checks: checks}
  end

  defp checks(:core, _host) do
    Enum.map([:jido, :jido_vfs, :jido_shell, :lua, :erlexec], &dependency/1)
  end

  defp checks(:native, _host) do
    helper = dependency(:erlexec)

    [
      helper,
      case command("/bin/sh", ["-c", "exit 0"]) do
        {:ok, _} -> ok(:process_launch, "erlexec launched a native process")
        _ -> missing(:process_launch, "Check the erlexec build and native process permissions")
      end
    ]
  end

  defp checks(:docker, _host) do
    with executable when is_binary(executable) <- System.find_executable("docker") do
      prefix =
        case System.get_env("JIDO_REALM_DOCKER_CONTEXT") do
          nil -> []
          context -> ["--context", context]
        end

      case version(executable, prefix ++ ["version", "--format", "{{.Server.Version}}"]) do
        {:ok, version} ->
          [ok(:docker_engine, version) | docker_images(executable, prefix)]

        _ ->
          [missing(:docker_engine, "Check Docker Engine and JIDO_REALM_DOCKER_CONTEXT")]
      end
    else
      nil -> [missing(:docker_cli, "Install Docker and add docker to PATH")]
    end
  end

  defp checks(:browser, _host) do
    chrome =
      System.get_env("JIDO_REALM_CHROME") || System.find_executable("chromium") ||
        System.find_executable("google-chrome") || @chrome

    [
      case version(System.find_executable("node"), ["--version"]) do
        {:ok, version} -> ok(:node, version)
        _ -> missing(:node, "Install a working Node.js executable")
      end,
      case System.find_executable(chrome) do
        nil -> missing(:chrome, "Install Chromium or set JIDO_REALM_CHROME to an executable")
        _ -> ok(:chrome, "Chrome or Chromium executable found")
      end
    ]
  end

  defp checks(:apple_container, %{os: :darwin, architecture: arch}) do
    if String.starts_with?(arch, ["aarch64-", "arm64-"]) do
      apple_container(System.find_executable("container"))
    else
      [missing(:apple_silicon, "Use an Apple silicon host with native Elixir and Erlang")]
    end
  end

  defp checks(:apple_container, _host),
    do: [missing(:apple_silicon, "Use Apple silicon and macOS for this lane")]

  defp checks(:sprites, _host), do: [dependency(:sprites), credential("SPRITES_TOKEN")]

  defp checks(:live_sprite, _host), do: [dependency(:sprites), credential("SPRITES_TEST_TOKEN")]

  defp checks(:lmstudio, _host) do
    case :gen_tcp.connect({127, 0, 0, 1}, 1234, [:binary, active: false], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        [ok(:lmstudio_listener, "Port 1234 accepts connections. Model and auth are unverified")]

      {:error, _} ->
        [missing(:lmstudio_listener, "Start the LM Studio server on localhost port 1234")]
    end
  end

  defp docker_images(executable, prefix) do
    Enum.map(@docker_images, fn {id, {variable, default}} ->
      image = System.get_env(variable, default)
      format = "{{.Os}} {{if .Config.Volumes}}volumes{{else}}no-volumes{{end}}"

      case command(executable, prefix ++ ["image", "inspect", "--format", format, "--", image]) do
        {:ok, "linux no-volumes"} ->
          ok(id, "Cached Linux image without declared volumes")

        _ ->
          missing(id, "Cache a Linux image without declared volumes for #{variable} (#{default})")
      end
    end)
  end

  defp apple_container(nil), do: [missing(:container_cli, "Install Apple's container CLI")]

  defp apple_container(executable) do
    case command(executable, ["system", "status"]) do
      {:ok, _} ->
        image = System.get_env("JIDO_REALM_APPLE_IMAGE", "alpine:latest")

        [
          ok(:container_system, "The container system status check passed"),
          case command(executable, ["image", "inspect", image]) do
            {:ok, _} ->
              ok(:container_image, "The configured image is cached")

            _ ->
              missing(
                :container_image,
                "Cache the image set by JIDO_REALM_APPLE_IMAGE (alpine:latest)"
              )
          end
        ]

      _ ->
        [missing(:container_system, "Check Apple Container with container system status")]
    end
  end

  defp dependency(app) do
    with result when result == :ok or result == {:error, {:already_loaded, app}} <-
           Application.load(app),
         version when is_list(version) <- Application.spec(app, :vsn) do
      ok(app, List.to_string(version))
    else
      _ -> missing(app, "Fetch and compile the #{app} dependency")
    end
  end

  defp credential(variable) do
    if String.trim(System.get_env(variable, "")) == "" do
      missing(variable, "Set #{variable} for this lane")
    else
      ok(variable, "Credential present. Authorization is unverified")
    end
  end

  defp version(executable, args) do
    with {:ok, output} <- command(executable, args),
         true <- Regex.match?(~r/\Av?\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.+-]+)?\z/, output) do
      {:ok, output}
    else
      _ -> :error
    end
  end

  defp command(nil, _args), do: :error

  defp command(executable, args) do
    with {:ok, _} <- Application.ensure_all_started(:erlexec) do
      task = Task.async(fn -> run_command([executable | args]) end)

      case Task.yield(task, @command_timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:ok, output}} ->
          {:ok, output |> Keyword.get(:stdout, []) |> IO.iodata_to_binary() |> String.trim()}

        _ ->
          :error
      end
    else
      _ -> :error
    end
  end

  defp run_command(command) do
    Process.flag(:trap_exit, true)

    :exec.run_link(
      command,
      [
        :sync,
        :stdout,
        {:stderr, :null},
        {:stdin, :close},
        {:group, 0},
        :kill_group,
        {:kill_timeout, 1}
      ],
      @command_timeout
    )
  catch
    :exit, _ -> :error
  end

  defp ok(id, detail), do: %{id: id, status: :ok, detail: detail}
  defp missing(id, detail), do: %{id: id, status: :missing, detail: detail}
end
