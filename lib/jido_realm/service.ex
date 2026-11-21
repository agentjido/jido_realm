defmodule Jido.Realm.Service do
  @moduledoc false

  alias Jido.Realm.Coding.Request
  alias Jido.Realm.Runner

  def prepare(services) when is_map(services) do
    for {name, %{exec: exec, ports: ports} = service} <- services,
        is_atom(name),
        is_map(ports),
        [{port_name, port}] <- [Map.to_list(ports)],
        is_atom(port_name) and port in 1..65_535,
        into: %{} do
      {name,
       %{
         exec: exec,
         port_name: port_name,
         port: port,
         options: Map.get(service, :options, []),
         require_check: Map.get(service, :require_check)
       }}
    end
  end

  def prepare(_), do: %{}

  def fetch(services, name) do
    case Map.fetch(services, name) do
      {:ok, config} -> {:ok, config}
      :error -> {:error, :unknown_service}
    end
  end

  def request(config, source_ref, max_run_ms) do
    with {:ok, request} <- build(config.exec, config.options),
         false <- Map.has_key?(request, :outputs) do
      {:ok,
       Map.merge(request, %{
         kind: :service,
         source_ref: source_ref,
         port: config.port,
         timeout_ms: min(request.timeout_ms, max_run_ms)
       })}
    else
      true -> {:error, :invalid_run_options}
      error -> error
    end
  end

  defp build({:entrypoint, runtime, path}, options) do
    with {:ok, request} <- Runner.preview_request(runtime, path, options),
         do: {:ok, %{request | id: new_id()}}
  end

  defp build({:shell, :bash, command}, options) do
    with true <- Keyword.keyword?(options),
         {:ok, options} <- Keyword.validate(options, [:cwd, :timeout_ms]) do
      Request.build(:bash, Map.put(Map.new(options), :command, command), new_id(), %{})
    else
      _ -> {:error, :invalid_run_options}
    end
  end

  defp build(_, _), do: {:error, :invalid_run_options}

  defp new_id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  def endpoint(service, gateway, opts) do
    case opts[:access] do
      :private -> {:ok, service.private || route(gateway.base)}
      :public -> public_endpoint(gateway.sharing, opts[:ttl_ms])
    end
  end

  defp public_endpoint(nil, _), do: {:error, :public_preview_unavailable}

  defp public_endpoint(%{base: base, max_ttl: max_ttl}, ttl)
       when is_integer(ttl) and ttl >= 1 and ttl <= max_ttl,
       do: {:ok, Map.put(route(base), :expires, System.monotonic_time(:millisecond) + ttl)}

  defp public_endpoint(_, _), do: {:error, :invalid_preview_ttl}

  defp route(base) do
    id = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    %{id: id, url: base <> "/" <> id <> "/"}
  end
end
