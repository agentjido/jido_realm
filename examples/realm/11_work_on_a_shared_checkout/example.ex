defmodule Jido.Realm.Examples.SharedCheckout do
  @moduledoc false

  alias Jido.Realm
  alias Jido.Realm.{Plugin, Provider, Session}

  defmodule Handoff do
    use Jido.Action,
      name: "shared_checkout_handoff",
      schema:
        Jido.Joi.object(%{
          operation: Jido.Joi.atom(),
          id: Jido.Joi.string()
        })

    @impl true
    def run(%{operation: operation, id: id}, context) do
      result =
        case operation do
          :wait -> Realm.exec(context, :work, {:command, :wait, %{}}, request_id: id)
          :check -> Realm.exec(context, :work, {:command, :verify, %{}}, request_id: id)
          :save -> Realm.save(context, :work, verified_by: id)
        end

      case result do
        {:ok, data} ->
          {:ok, signal} = Jido.Agent.build_signal(context, "checkout.result", data)
          {:ok, context.agent_state, [Jido.Agent.Directive.reply(signal)]}

        {:error, reason} ->
          {:error,
           Jido.Error.execution_error("Checkout action failed", details: %{reason: reason})}
      end
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "realm_shared_checkout", plugins: [Plugin]

    realms do
      realm(:work, profile: :program)
    end

    routes do
      signal_source("/examples/shared-checkout")
      route("checkout.handoff", Handoff)
    end
  end

  def session(profile, opts \\ []) do
    provider_opts = [profile: profile, check_files: ["source.txt"]] ++ opts

    Session.start_link(
      provider: {Provider.SharedCheckout, provider_opts},
      commands: %{
        wait: %{
          grant: :run,
          schema: Jido.Joi.object(%{}),
          exec: {:shell, :bash, "sleep 30"},
          options: [timeout_ms: 1_000]
        },
        verify: %{
          grant: :run,
          schema: Jido.Joi.object(%{}),
          exec:
            {:check, :bash, ~S|test "$(cat source.txt)" = 42 && echo "verified 42" > report.txt|}
        }
      }
    )
  end

  def start_agent(instance, session, grants) do
    {:ok, agent} =
      Jido.start_agent(instance, Agent,
        id: "checkout-#{System.unique_integer([:positive])}",
        plugin_runtime_options: [{Plugin, bindings: %{work: [session: session, grants: grants]}}]
      )

    :ok = Jido.AgentServer.await_ready(agent)
    agent
  end

  def call(agent, type, params \\ %{}) do
    signal =
      Jido.Signal.new!(type, Map.put(params, :realm, :work), source: "/examples/shared-checkout")

    Jido.AgentServer.call(agent, signal, timeout: 20_000)
  end

  def review(profile, from, stores) do
    Application.put_env(:jido_realm, :stores, stores)
    {:ok, _} = Jido.start(name: __MODULE__)
    {:ok, session} = session(profile, from: from)
    reader = start_agent(__MODULE__, session, [:open, :close, :read, :run])

    {:ok, %{status: :committed}} = call(reader, "realm.open")

    {:ok, %{status: :committed, reply: %{data: %{content: report}}}} =
      call(reader, "realm.file.read", %{path: "report.txt"})

    {:ok, %{status: :failed, error: %{details: %{reason: :permission_denied}}}} =
      call(reader, "realm.file.edit", %{path: "report.txt", content: "unverified"})

    {:ok, %{status: :committed, reply: %{data: %{status: :failed}}}} =
      call(reader, "checkout.handoff", %{operation: :check, id: "read-only-check"})

    {:ok, %{status: :committed, reply: %{data: %{content: ^report}}}} =
      call(reader, "realm.file.read", %{path: "report.txt"})

    {:ok, %{status: :committed}} = call(reader, "realm.close")
    report
  end
end
