defmodule Jido.Realm.Runner.Docker.Engine do
  @moduledoc false

  alias Jido.Realm.Runner.CLI

  @timeout 3_000

  def connect(opts) do
    with executable when is_binary(executable) <- System.find_executable("docker"),
         {:ok, prefix} <- context(opts[:context]) do
      {:ok, %{docker: executable, prefix: prefix, network: opts[:network]}}
    else
      _ -> {:error, :runtime_unavailable}
    end
  end

  def image_identity(config, image) do
    args = [
      "image",
      "inspect",
      "--format",
      ~S|{{.Id}} {{.Os}} {{with index .Config "Volumes"}}volumes{{else}}no-volumes{{end}}|,
      "--",
      image
    ]

    with {0, info} <- command(config, args),
         [id, "linux", "no-volumes"] <- String.split(info),
         true <- Regex.match?(~r/^sha256:[0-9a-f]{64}$/, id) do
      {:ok, id}
    else
      _ -> {:error, :image_unavailable}
    end
  end

  def create(config, args, timeout, watch),
    do: command(config, ["container", "create" | args], timeout, watch)

  def boot(config, name), do: command(config, ["container", "start", name])

  def attach(config, name, timeout, watch, on_output \\ nil),
    do: command(config, ["container", "start", "--attach", name], timeout, watch, on_output)

  def remove(config, name) do
    case command(config, ["container", "rm", "--force", "--volumes", name]) do
      {0, _} -> :ok
      _ -> {:error, :unknown}
    end
  end

  def absent?(config, name) do
    args = ["container", "ls", "--all", "--filter", "name=^/#{name}$", "--format", "{{.Names}}"]
    command(config, args) == {0, ""}
  end

  def running?(config, name),
    do:
      command(config, ["container", "inspect", "--format", "{{.State.Running}}", name]) ==
        {0, "true\n"}

  def logs(config, name) do
    {_, output} = command(config, ["container", "logs", "--tail", "50", name])
    String.replace_invalid(output, "?")
  end

  def host_port(_), do: {:ok, nil}

  def published_port(config, name, guest_port, _) do
    with {0, "127.0.0.1:" <> port} <-
           command(config, ["container", "port", name, "#{guest_port}/tcp"]),
         {port, ""} when port in 1..65_535 <- Integer.parse(String.trim(port)) do
      {:ok, port}
    else
      _ -> {:error, :preview_port_unavailable}
    end
  end

  def preview_network(%{network: network} = config) when is_binary(network) and network != "" do
    if command(config, ["network", "inspect", "--format={{.Driver}}", "--", network]) ==
         {0, "bridge\n"},
       do: :ok,
       else: {:error, :private_network_unavailable}
  end

  def preview_network(_), do: {:error, :private_network_unavailable}

  def mount_options, do: ",bind-recursive=disabled"

  def run_flags, do: ["--network", "none", "--log-driver", "none"]

  def preview_flags(config, _host_port, port) do
    [
      "--network",
      config.network,
      "--publish=127.0.0.1::#{port}/tcp",
      "--env=PORT=#{port}",
      "--log-driver=local",
      "--log-opt=max-size=64k",
      "--log-opt=compress=false",
      "--log-opt=max-file=1"
    ]
  end

  def staged_flags do
    [
      "--pull=never",
      "--security-opt=no-new-privileges=true",
      "--pids-limit=256",
      "--ipc=none",
      "--tmpfs",
      "/tmp:rw,nosuid,nodev,size=128m,mode=1777"
    ]
  end

  def pinned_image(_image, identity), do: identity

  def command(config, args, timeout \\ @timeout, watch \\ nil, on_output \\ nil),
    do: CLI.run(config.docker, config.prefix ++ args, timeout, watch, on_output: on_output)

  defp context(nil), do: {:ok, []}
  defp context(name) when is_binary(name) and name != "", do: {:ok, ["--context", name]}
  defp context(_), do: {:error, :invalid_runtime_context}
end
