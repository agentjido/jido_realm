defmodule Jido.Realm.Conformance.AgentJobs do
  @moduledoc false

  import ExUnit.Assertions

  defmodule Job do
    @moduledoc false
    use Jido.Action,
      name: "perform_realm_job",
      schema:
        Jido.Joi.object(%{
          job: Jido.Joi.atom(),
          realm: Jido.Joi.atom() |> Jido.Joi.optional(),
          path: Jido.Joi.string() |> Jido.Joi.optional(),
          to: Jido.Joi.string() |> Jido.Joi.optional(),
          text: Jido.Joi.string() |> Jido.Joi.optional(),
          replace: Jido.Joi.boolean() |> Jido.Joi.optional(),
          chunk_size: Jido.Joi.integer() |> Jido.Joi.optional(),
          paths: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.optional(),
          command: Jido.Joi.atom() |> Jido.Joi.optional(),
          input: Jido.Joi.map() |> Jido.Joi.optional(),
          id: Jido.Joi.string() |> Jido.Joi.optional()
        })

    alias Jido.Agent.Directive
    alias Jido.Realm

    @impl true
    def run(input, context) do
      case perform(input, context) do
        {:ok, data} ->
          {:ok, reply} = Jido.Agent.build_signal(context, "realm.job.result", data)
          {:ok, context.agent_state, [Directive.reply(reply)]}

        :ok ->
          {:ok, reply} = Jido.Agent.build_signal(context, "realm.job.result", %{})
          {:ok, context.agent_state, [Directive.reply(reply)]}

        {:error, reason} ->
          {:error, Jido.Error.execution_error("Realm job failed", details: %{reason: reason})}
      end
    end

    defp perform(%{job: :organize, realm: realm, path: path, to: to, text: text}, context) do
      with {:ok, _} <- Realm.file(context, realm, :create, path, text),
           {:ok, %{content: draft}} <- Realm.file(context, realm, :read, path),
           {:ok, _} <- Realm.file(context, realm, :create, to, draft),
           {:ok, _} <- Realm.file(context, realm, :delete, path) do
        {:ok, %{path: to}}
      end
    end

    defp perform(%{job: job, realm: realm}, context) when job in [:open, :close],
      do: apply(Realm, job, [context, realm])

    defp perform(%{job: job, path: path, to: to}, context) when job in [:copy, :move],
      do: apply(Realm, job, [context, {:source, path}, {:target, to}])

    defp perform(%{job: :stream, path: path, to: to} = input, context) do
      Realm.copy_stream(context, {:source, path}, {:target, to},
        chunk_size: Map.get(input, :chunk_size, 64),
        replace: Map.get(input, :replace, false)
      )
    end

    defp perform(%{job: :publish, realm: realm, path: entrypoint, paths: paths}, context),
      do: Realm.publish_artifact(context, realm, entrypoint, paths)

    defp perform(%{job: :commands, realm: realm}, context) do
      with {:ok, commands} <- Realm.commands(context, realm), do: {:ok, %{commands: commands}}
    end

    defp perform(%{job: :invoke, realm: realm, command: command, input: input}, context),
      do: Realm.invoke(context, realm, command, input)

    defp perform(%{job: :start_background, realm: realm, path: path}, context),
      do: Realm.start_run(context, realm, :lua, path, timeout_ms: 5_000)

    defp perform(%{job: :run_status, realm: realm, id: id}, context),
      do: Realm.run_status(context, realm, id)

    defp perform(%{job: :save_binary, realm: realm, path: path, text: encoded}, context) do
      case Base.decode64(String.trim(encoded)) do
        {:ok, bytes} -> Realm.file(context, realm, :write_stream, path, {[bytes], false})
        :error -> {:error, :invalid_build_output}
      end
    end
  end

  defmodule Work do
    @moduledoc false
    use Jido.Agent, name: "realm_integration_work", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:work, profile: :files)
    end

    routes do
      signal_source("/test/realm/jobs")
      route("realm.job", Job)
    end
  end

  defmodule Pair do
    @moduledoc false
    use Jido.Agent, name: "realm_integration_pair", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:source, profile: :files)
      realm(:target, profile: :files)
    end

    routes do
      signal_source("/test/realm/jobs")
      route("realm.job", Job)
    end
  end

  defmodule Programmer do
    @moduledoc false
    use Jido.Agent, name: "realm_integration_programmer", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:work, profile: :program)
    end

    routes do
      signal_source("/test/realm/programs")
      route("realm.job", Job)
    end
  end

  def run_program(agent, runtime, entrypoint, opts \\ %{}) do
    data = Map.merge(opts, %{realm: "work", runtime: runtime, entrypoint: entrypoint})
    signal = Jido.Signal.new!("realm.program.run", data, source: "/test")
    Jido.AgentServer.call(agent, signal, timeout: 25_000)
  end

  def run_result(agent, runtime, entrypoint, opts \\ %{}) do
    assert {:ok, %{status: :committed, reply: %{type: "realm.program.result", data: result}}} =
             run_program(agent, runtime, entrypoint, opts)

    result
  end

  defmodule RestrictedProfile do
    @moduledoc false
    @behaviour Jido.Realm.Profile
    @impl true
    def requirements do
      %Jido.Realm.Profile{required: [:files, :isolation], optional: [:tree, :search, :streams]}
    end
  end

  defmodule Restricted do
    @moduledoc false
    use Jido.Agent, name: "realm_integration_restricted", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:work, profile: Jido.Realm.Conformance.AgentJobs.RestrictedProfile)
    end

    routes do
      signal_source("/test/realm/jobs")
      route("realm.job", Job)
    end
  end

  def call(agent, job, data \\ %{}) do
    signal = Jido.Signal.new!("realm.job", Map.put(data, :job, job), source: "/test")
    Jido.AgentServer.call(agent, signal)
  end

  def succeeded(agent, job, data \\ %{}) do
    assert {:ok, %{status: :committed, reply: %{type: "realm.job.result", data: reply}}} =
             call(agent, job, data)

    reply
  end

  def rejected(agent, job, reason, data \\ %{}) do
    assert {:ok, %{status: :failed, reply: nil, error: %{details: %{reason: ^reason}}}} =
             call(agent, job, data)
  end
end
