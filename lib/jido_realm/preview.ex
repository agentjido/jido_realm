defmodule Jido.Realm.Preview do
  @moduledoc """
  Adapter for a private HTTP service. The host configures the adapter, its
  network policy, and the private gateway used by reviewers.

  The adapter returns a target only after readiness. On an unconfirmed start
  or stop it must keep a handle that Realm can use to retry cleanup.
  """

  alias Jido.Realm.{Provider, Runner, Session}

  @type target :: %{host: String.t(), port: pos_integer()}
  @callback prepare(Provider.lease(), term()) :: {:ok, term()} | {:error, term()}
  @callback start(term(), Runner.request()) ::
              {:ok, term(), target()} | {:error, term()} | {:error, term(), term()}
  @callback stop(term(), term()) :: :ok | {:error, term()}

  @doc "Reports whether the process that owns the preview is still running."
  @callback running?(term()) :: boolean()
  @doc "Reports whether the adapter checks the verified source before service launch."
  @callback verified_source?(term()) :: boolean()
  @optional_callbacks running?: 1, verified_source?: 1

  @doc false
  def verify_source(_, nil), do: :ok

  def verify_source(%{module: module, state: adapter}, _) do
    if function_exported?(module, :verified_source?, 1) and module.verified_source?(adapter),
      do: :ok,
      else: {:error, :verified_service_unavailable}
  end

  @doc false
  def running?(%{module: module}, handle),
    do: not function_exported?(module, :running?, 1) or module.running?(handle)

  @doc "Resolves a route for an identity authenticated by the host gateway."
  def target(session, id, viewer), do: Session.preview_target(session, id, {:private, viewer})

  @doc "Resolves an anonymous route on the host gateway’s HTTPS listener."
  def public_target(session, id), do: Session.preview_target(session, id, :public)

  @doc false
  def prepare({:native, options}, lease, opts),
    do: prepare({__MODULE__.Native, options}, lease, opts)

  @doc false
  def prepare({module, options}, lease, opts) when is_atom(module) do
    with {:ok, base} <- base_url(opts[:preview_base_url], ["http", "https"]),
         viewers when is_list(viewers) <- opts[:preview_viewers],
         {:ok, prepared} <- module.prepare(lease, options) do
      %{
        module: module,
        state: prepared,
        base: base,
        viewers: MapSet.new(viewers),
        sharing: prepare_sharing(opts)
      }
    else
      _ -> nil
    end
  end

  def prepare(_, _, _), do: nil

  @doc false
  def ready?(port) do
    case :gen_tcp.connect(
           {127, 0, 0, 1},
           port,
           [:binary, active: false, packet: :line, packet_size: 1024],
           100
         ) do
      {:ok, socket} ->
        try do
          with :ok <-
                 :gen_tcp.send(
                   socket,
                   "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
                 ),
               {:ok, status} <- :gen_tcp.recv(socket, 0, 100) do
            Regex.match?(~r/\AHTTP\/1\.[01] 2\d\d /, status)
          else
            _ -> false
          end
        after
          :gen_tcp.close(socket)
        end

      _ ->
        false
    end
  end

  defp prepare_sharing(opts) do
    with {:ok, base} <- base_url(opts[:preview_public_base_url], ["https"]),
         max_ttl when is_integer(max_ttl) and max_ttl > 0 <- opts[:preview_max_public_ms] do
      %{base: base, max_ttl: max_ttl}
    else
      _ -> nil
    end
  end

  defp base_url(url, schemes) when is_binary(url) do
    with %{scheme: scheme, host: host, query: nil, fragment: nil, userinfo: nil} <- URI.parse(url),
         true <- scheme in schemes and is_binary(host) and host != "" do
      {:ok, String.trim_trailing(url, "/")}
    else
      _ -> :error
    end
  end

  defp base_url(_, _), do: :error
end
