defmodule RealmWorkbench.Runs do
  use GenServer

  alias Jido.Realm.Session
  alias RealmWorkbench.{CodingAgent, Provider}

  @providers ~w(local docker apple sprites)
  @recipes ~w(phoenix typescript)
  @max_active 8

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def model, do: System.get_env("WORKBENCH_MODEL", "inkling-2-mini")
  def base_url, do: System.get_env("WORKBENCH_LLM_URL", "http://127.0.0.1:1234/v1")
  def list, do: GenServer.call(__MODULE__, :list)
  def log_tail(id), do: GenServer.call(__MODULE__, {:log_tail, id})
  def resource(id, app), do: GenServer.call(__MODULE__, {:resource, id, app})
  def log(id, message), do: GenServer.cast(__MODULE__, {:log, id, message})

  def start(provider, recipe) when provider in @providers and recipe in @recipes,
    do: GenServer.call(__MODULE__, {:start, provider, recipe})

  def start(_, _), do: {:error, "Select a provider and a recipe from the list."}

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)
    {:ok, %{rows: %{}, resources: %{}}}
  end

  @impl true
  def handle_call(:list, _from, state),
    do: {:reply, Enum.sort_by(Map.values(state.rows), & &1.started_at, :desc), state}

  def handle_call({:log_tail, id}, _from, state) do
    logs = get_in(state.rows, [id, :logs]) || []
    {:reply, logs |> Enum.take(-12) |> Enum.join("\n"), state}
  end

  def handle_call({:resource, id, app}, _from, state),
    do: {:reply, :ok, put_in(state.resources[id], app)}

  def handle_call({:start, provider, recipe}, _from, state) do
    if Enum.count(state.rows, fn {_, row} -> row.status == :running end) >= @max_active do
      {:reply, {:error, "Wait for a running build to finish."}, state}
    else
      id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      job = job(id, provider, recipe)

      row = %{
        id: id,
        provider: provider,
        recipe: recipe,
        model: model(),
        status: :running,
        started_at: System.system_time(:millisecond),
        logs: [],
        files: %{},
        url: nil,
        http_status: nil,
        error: nil
      }

      {:ok, _} = Task.Supervisor.start_child(RealmWorkbench.Tasks, fn -> run(job) end)
      {:reply, {:ok, id}, put_in(state.rows[id], row)}
    end
  end

  @impl true
  def handle_cast({:log, id, text}, state) do
    {:noreply,
     update_in(state.rows[id].logs, &Enum.take(&1 ++ [String.slice(text, 0, 2_000)], -90))}
  end

  def handle_cast({:finished, id, {:ok, result}}, state),
    do: {:noreply, update_in(state.rows[id], &Map.merge(&1, Map.put(result, :status, :passed)))}

  def handle_cast({:finished, id, {:error, reason}}, state) do
    {:noreply, update_in(state.rows[id], &Map.merge(&1, %{status: :failed, error: reason}))}
  end

  @impl true
  def terminate(_, state), do: Enum.each(state.resources, fn {_, app} -> Provider.stop(app) end)

  defp job(id, provider, recipe) do
    root =
      if provider == "sprites",
        do: "/home/sprite/.jido-workbench/#{id}",
        else: Path.join(Application.fetch_env!(:realm_workbench, :runs_dir), id)

    %{id: id, provider: provider, recipe: recipe, root: root}
  end

  defp run(job) do
    result =
      try do
        run_agent(job)
      rescue
        error -> {:error, Exception.message(error)}
      catch
        :exit, _ -> {:error, "The coding agent stopped before returning its result."}
      end

    GenServer.cast(__MODULE__, {:finished, job.id, result})
  end

  defp run_agent(job) do
    {:ok, session} =
      Session.start_link(
        provider: {Provider, job},
        commands: %{
          start_preview: %{
            schema: Jido.Joi.object(%{}),
            grant: :run,
            read: [],
            run: fn %{}, _ -> Provider.launch(job) end
          }
        }
      )

    instance = RealmWorkbench.Jido
    grants = [:open, :close, :read, :write, :run]
    runtime = [bindings: %{work: [session: session, grants: grants]}]

    {:ok, agent} =
      Jido.start_agent(instance, CodingAgent,
        id: job.id,
        turn_timeout: 540_000,
        plugin_runtime_options: [{Jido.Realm.Plugin, runtime}]
      )

    try do
      :ok = Jido.AgentServer.await_ready(agent)

      signal =
        Jido.Signal.new!("workbench.build", Map.take(job, [:id, :provider, :recipe]),
          source: "/workbench"
        )

      case Jido.AgentServer.call(agent, signal, timeout: 600_000) do
        {:ok, %{status: :committed, reply: %{data: result}}} -> {:ok, result}
        {:ok, %{error: %{details: %{reason: reason}}}} -> {:error, reason}
        {:ok, %{status: :timed_out}} -> {:error, "The build exceeded its turn deadline."}
        {:ok, %{error: error}} -> {:error, inspect(error)}
        {:error, _} -> {:error, "The Jido turn timed out or lost its reply."}
      end
    after
      Jido.stop_agent(instance, agent)
      GenServer.stop(session)
    end
  end
end
