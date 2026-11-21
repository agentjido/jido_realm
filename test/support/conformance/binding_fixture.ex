defmodule Jido.Realm.Conformance.BindingFixture do
  @moduledoc false
  @behaviour Jido.Realm.Conformance.Fixture

  alias Jido.Realm.{Local, Memory, Placement, Session}

  defmodule Recorded do
    @moduledoc false
    @behaviour Jido.Realm.Provider
    alias Jido.Realm.Conformance.BindingFixture
    alias Jido.Realm.Placement

    def open(opts) do
      with {:ok, lease} <- Placement.open(opts.placement) do
        {backend, handle} = lease.binding

        Enum.each(opts.files, fn {path, bytes} ->
          BindingFixture.seed(backend, handle, path, bytes)
        end)

        Agent.update(opts.record, &Map.put(&1, :lease, lease))
        send(opts.owner, {:placement_opened, opts.realm, lease.placement})
        capabilities = Map.merge(lease.capabilities, opts.capabilities)

        {:ok,
         %{lease | binding: {__MODULE__, {lease.binding, opts.hook}}, capabilities: capabilities}}
      end
    end

    def close(_lease, opts) do
      %{lease: lease, released: released} = Agent.get(opts.record, & &1)

      if released do
        :ok
      else
        with :ok <- Placement.close(lease, []) do
          Agent.update(opts.record, &Map.put(&1, :released, true))
          send(opts.owner, {:placement_released, opts.realm, lease.ownership})
          if opts.lose_release, do: {:error, :unknown}, else: :ok
        end
      end
    end

    def run({{module, handle}, hook}, operation, path, input) do
      hook.(operation, path, input, fn -> module.run(handle, operation, path, input) end)
    end
  end

  @impl true
  def prepare(%{fixture_options: opts, realm: realm}) do
    kind = Keyword.fetch!(opts, :kind)
    mode = Keyword.get(opts, :mode, :borrowed)
    grants = Keyword.get(opts, :grants, :all)
    placement = placement(kind, mode)
    default_hook = fn _, _, _, run -> run.() end
    hook = Keyword.get(opts, :hook, default_hook)

    {runtime, where} =
      case mode do
        :static ->
          {:borrow, {_, handle} = binding} = placement
          {[backend: {Recorded, {binding, hook}}, grants: grants], fn -> handle end}

        _ ->
          record =
            ExUnit.Callbacks.start_supervised!({Agent, fn -> %{lease: nil, released: false} end},
              id: make_ref()
            )

          provider_options = %{
            placement: placement,
            record: record,
            owner: self(),
            realm: realm,
            hook: hook,
            files: Keyword.get(opts, :files, %{}),
            capabilities: Keyword.get(opts, :report, %{}),
            lose_release: Keyword.get(opts, :lose_release, false)
          }

          session =
            ExUnit.Callbacks.start_supervised!(
              {Session,
               provider: {Recorded, provider_options},
               owner: Keyword.get(opts, :owner),
               runners: Keyword.get(opts, :runners, %{}),
               max_run_ms: Keyword.get(opts, :max_run_ms, 20_000),
               capabilities: Keyword.get(opts, :permitted, :all),
               commands: Keyword.get(opts, :commands, %{}),
               services: Keyword.get(opts, :services, %{}),
               preview: opts[:preview],
               preview_base_url: opts[:preview_base_url],
               preview_public_base_url: opts[:preview_public_base_url],
               preview_max_public_ms: opts[:preview_max_public_ms],
               preview_viewers: opts[:preview_viewers]},
              id: make_ref()
            )

          options = [session: session, grants: grants]

          {options, fn -> Agent.get(record, &get_in(&1, [:lease, :placement])) end}
      end

    runtime =
      case Keyword.fetch(opts, :presenter) do
        {:ok, presenter} -> Keyword.put(runtime, :presenter, presenter)
        :error -> runtime
      end

    %{
      runtime_options: runtime,
      ownership: if(mode == :owned, do: :owned, else: :borrowed),
      owner: Keyword.get(opts, :owner),
      where: where,
      observe: fn path -> observe(kind, where.(), path) end,
      seed: fn path, bytes -> seed(kind, where.(), path, bytes) end
    }
  end

  defp placement(:memory, :owned), do: :memory

  defp placement(:memory, _) do
    {:borrow, {Memory, ExUnit.Callbacks.start_supervised!(Memory, id: make_ref())}}
  end

  defp placement(:local, mode) do
    root =
      Path.join(
        System.tmp_dir!(),
        "jido-realm-integration-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)

    case mode do
      :owned ->
        {:local, root}

      _ ->
        File.mkdir!(root)
        {:borrow, {Local, root}}
    end
  end

  defp observe(:local, root, path) when is_binary(root) do
    case File.read(Path.join(root, path)) do
      {:error, :enoent} -> {:error, :not_found}
      result -> result
    end
  end

  defp observe(:memory, pid, path) when is_pid(pid) do
    if Process.alive?(pid) do
      case Agent.get(pid, &Map.fetch(&1, path)) do
        :error -> {:error, :not_found}
        result -> result
      end
    else
      {:error, :not_found}
    end
  end

  defp observe(_, nil, _), do: {:error, :not_found}

  def seed(kind, root, path, bytes) when kind in [:local, Local] do
    file = Path.join(root, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, bytes)
  end

  def seed(kind, pid, path, bytes) when kind in [:memory, Memory] do
    Agent.update(pid, fn entries ->
      parts = Path.split(path)
      parent_paths = parts |> Enum.drop(-1) |> Enum.scan(&Path.join(&2, &1))
      entries = Enum.reduce(parent_paths, entries, &Map.put_new(&2, &1, :directory))
      Map.put(entries, path, bytes)
    end)
  end
end
