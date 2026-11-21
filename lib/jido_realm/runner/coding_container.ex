defmodule Jido.Realm.Runner.CodingContainer do
  @moduledoc """
  Compatibility adapter for existing `:engine` configurations.
  For new configurations use `Jido.Realm.Runner.Docker` with `:staged`
  options, or `Jido.Realm.Runner.AppleContainer`.
  """

  @behaviour Jido.Realm.Runner
  @behaviour Jido.Realm.Preview

  alias Jido.Realm.Runner.{AppleContainer, Docker, Staged}

  @impl Jido.Realm.Runner
  def prepare(runtime, lease, opts) do
    case engine(opts) do
      {:ok, engine, opts} -> Staged.prepare(engine, runtime, lease, opts)
      error -> error
    end
  end

  @impl Jido.Realm.Preview
  def prepare(lease, opts) do
    case engine(opts) do
      {:ok, engine, opts} -> Staged.prepare_service(engine, lease, opts)
      error -> error
    end
  end

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

  defp engine(opts) do
    {engine, opts} = Keyword.pop(opts, :engine)

    opts =
      opts
      |> Keyword.put_new(:grep, true)
      |> Keyword.put_new(:probe, "bash --version && mix --version")
      |> Keyword.put_new(:env, %{"MIX_BUILD_PATH" => "/tmp/realm-build"})
      |> Keyword.put_new(:check_exits, %{78 => :setup_failed})

    case engine do
      :docker -> {:ok, Docker.Engine, opts}
      :apple_container -> {:ok, AppleContainer, opts}
      _ -> {:error, :runtime_unavailable}
    end
  end
end
