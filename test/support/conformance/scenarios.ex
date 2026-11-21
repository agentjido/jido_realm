defmodule Jido.Realm.Conformance.Scenarios do
  @moduledoc """
  Runs an agent job once for each named set of Realm fixtures.

  Declare the Realms in the agent DSL. Bind each name to a fixture in every
  `cases` entry. The test receives the job agent and a direct store reader
  for each Realm.
  """

  defmacro realm_case(description, options, do: [{:->, _, [[pattern], body]}]) do
    agent = Keyword.fetch!(options, :agent)
    cases = Keyword.fetch!(options, :cases)
    optional = Keyword.get(options, :opt_in, [])
    evidence = Keyword.get(options, :evidence, :real_store)
    variants = for {name, bindings} <- cases, do: {{name, bindings}, [realm_case: name]}

    variants =
      variants ++
        for {tag, entries} <- optional, {name, bindings} <- entries do
          {{name, bindings}, [{tag, true}, {:optional_realm_case, name}]}
        end

    if cases == [], do: raise(ArgumentError, "realm_case requires at least one default case")

    for {{name, bindings}, tags} <- variants do
      quote do
        @tag realm_evidence: unquote(evidence)
        @tag unquote(tags)
        test unquote("#{description} [#{name}, #{evidence}]"), context do
          unquote(pattern) =
            unquote(__MODULE__).prepare(context, unquote(agent), unquote(bindings), unquote(name))

          unquote(body)
        end
      end
    end
  end

  def prepare(context, agent_module, bindings, variant) do
    instance = context.module
    ExUnit.Callbacks.start_supervised!({Jido, name: instance})

    {runtime_bindings, observers} =
      Enum.reduce(bindings, {%{}, %{}}, fn {name, fixture}, {runtime_bindings, observers} ->
        {module, params} = if is_tuple(fixture), do: fixture, else: {fixture, []}
        fixture_context = Map.merge(context, %{realm: name, fixture_options: params})
        opened = module.prepare(fixture_context)

        {Map.put(runtime_bindings, name, opened.runtime_options),
         Map.put(observers, name, opened)}
      end)

    agent = start_agent(instance, agent_module, runtime_bindings)

    %{
      agent: agent,
      variant: variant,
      instance: instance,
      bindings: runtime_bindings,
      placements: observers,
      observe: Map.new(observers, fn {name, opened} -> {name, opened.observe} end)
    }
  end

  def start_agent(instance, agent_module, runtime_bindings) do
    start_agent(instance, agent_module, "realm-job-#{System.unique_integer([:positive])}",
      bindings: runtime_bindings
    )
  end

  def start_agent(instance, agent_module, id, runtime_options) do
    {:ok, agent} =
      Jido.start_agent(instance, agent_module,
        id: id,
        plugin_runtime_options: [{Jido.Realm.Plugin, runtime_options}]
      )

    :ok = Jido.AgentServer.await_ready(agent)
    agent
  end
end
