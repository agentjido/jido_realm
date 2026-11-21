defmodule Jido.Realm.LiveFileAgent.FileTool do
  @moduledoc false

  alias Jido.Joi
  alias Jido.Realm

  @operations %{"read" => :read, "create" => :create, "edit" => :edit, "delete" => :delete}

  use Jido.Action,
    name: "realm_file",
    description:
      "Read, create, replace, or delete one text file in a named Realm. " <>
        "Pass a relative path. For create and edit, pass the full file contents.",
    schema:
      Joi.object(
        %{
          realm: Joi.enum(["source", "work"]),
          path: Joi.string(),
          operation: Joi.enum(["read", "create", "edit", "delete"]),
          content: Joi.string() |> Joi.optional()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(%{realm: realm, path: path, operation: operation} = input, context) do
    case Realm.file(context, realm, Map.fetch!(@operations, operation), path, input[:content]) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, Jido.Error.execution_error("Realm file operation failed: #{inspect(reason)}")}
    end
  end
end

defmodule Jido.Realm.LiveFileAgent do
  @moduledoc false

  use Jido.AI.Agent, name: "realm_live_file_agent", plugins: [Jido.Realm.Plugin]

  realms do
    realm(:source, profile: :files)
    realm(:work, profile: :files)
  end

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      instructions(
        "Use realm_file for each file operation. Wait for each result before the next operation. Preserve exact file text."
      )

      limits do
        model_calls(10)
        tool_rounds(8)
        tool_calls(10)
        retries(0)
        elapsed_ms(120_000)
      end
    end

    tools do
      action(Jido.Realm.LiveFileAgent.FileTool)
    end
  end
end

defmodule Jido.Realm.Integration.LiveFileAgentTest do
  @moduledoc false

  @trials (case Integer.parse(System.get_env("JIDO_REALM_PRESSURE_RUNS", "1")) do
             {count, ""} when count in 1..50 -> count
             _ -> raise ArgumentError, "JIDO_REALM_PRESSURE_RUNS must be an integer from 1 to 50"
           end)

  use ExUnit.Case,
    async: true,
    parameterize:
      for(
        backend <- [:local, :memory],
        trial <- 1..@trials,
        do: %{backend: backend, trial: trial}
      )

  alias Jido.Realm.Conformance.{BindingFixture, Scenarios}
  alias Jido.Realm.LiveFileAgent

  @moduletag :lmstudio
  @moduletag timeout: 140_000

  test "Qwen manages real files and gets a denial from the read-only Realm", context do
    %{backend: backend, trial: trial} = context
    instance = Module.concat(__MODULE__, "#{backend}_#{trial}")
    start_supervised!({Jido, name: instance})

    source = fixture(context, :source, [:read])
    work = fixture(context, :work, [:read, :write])

    model = System.get_env("JIDO_REALM_LMSTUDIO_MODEL", "qwen3.8-27b-realm")
    token = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    note = "Case #{token}: café"
    input_path = "inbox-#{trial}.txt"
    output_path = "report-#{trial}.txt"
    draft_path = "old-draft-#{trial}.txt"

    source.seed.(input_path, note)
    work.seed.(draft_path, "Old draft")
    work.seed.("keep.txt", "Keep this file")

    agent =
      Scenarios.start_agent(instance, LiveFileAgent, %{
        source: source.runtime_options,
        work: work.runtime_options
      })

    signal =
      LiveFileAgent.request_signal!(%{
        model: "lmstudio:" <> model,
        options: %{
          base_url: "http://127.0.0.1:1234/v1",
          reasoning_effort: :none,
          max_tokens: 512,
          temperature: 0.2,
          max_retries: 0,
          receive_timeout: 60_000
        },
        input: """
        Use the realm_file tool to perform these steps in order. Each step is one tool call.
        1. Read #{input_path} in source.
        2. Create #{output_path} in work with the exact text you read.
        3. Edit #{output_path} in work. Replace its contents with `Reviewed: ` followed by the exact text you read in step 1.
        4. Delete #{draft_path} in work.
        5. Check that source is read-only. Try once to edit #{input_path} in source with the text `permission probe`.
        After the permission check, give a short summary and finish.
        """
      })

    started = System.monotonic_time(:millisecond)

    assert {:ok, %{status: :committed, reply: %{data: result}}} =
             Jido.AgentServer.call(agent, signal, 130_000)

    attempts = Enum.map(result.tool_attempts, &Map.take(&1, [:status, :input, :error]))
    assert result.status == :completed, inspect({result.status, result.reason, attempts})
    assert Enum.map(result.tool_attempts, & &1.tool_round) == [1, 2, 3, 4, 5]

    assert [
             %{
               status: :ok,
               input: %{"operation" => "read", "realm" => "source", "path" => ^input_path}
             },
             %{
               status: :ok,
               input: %{
                 "operation" => "create",
                 "realm" => "work",
                 "path" => ^output_path,
                 "content" => ^note
               }
             },
             %{
               status: :ok,
               input: %{"operation" => "edit", "realm" => "work", "path" => ^output_path}
             },
             %{
               status: :ok,
               input: %{"operation" => "delete", "realm" => "work", "path" => ^draft_path}
             },
             %{
               status: :error,
               input: %{"operation" => "edit", "realm" => "source", "path" => ^input_path},
               error: %{"message" => denial}
             }
           ] = attempts

    assert denial =~ "permission_denied"
    assert work.observe.(output_path) == {:ok, "Reviewed: " <> note}
    assert work.observe.(draft_path) == {:error, :not_found}
    assert work.observe.("keep.txt") == {:ok, "Keep this file"}
    assert source.observe.(input_path) == {:ok, note}

    elapsed_ms = System.monotonic_time(:millisecond) - started

    IO.puts(
      "#{model} #{backend} trial #{trial}: #{elapsed_ms} ms, #{result.model_calls} model calls"
    )
  end

  defp fixture(%{backend: backend} = context, realm, grants) do
    BindingFixture.prepare(
      Map.merge(context, %{
        realm: realm,
        fixture_options: [kind: backend, mode: :static, grants: grants]
      })
    )
  end
end
