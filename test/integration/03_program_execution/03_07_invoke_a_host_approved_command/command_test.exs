defmodule Jido.Realm.Integration.CommandTest do
  use ExUnit.Case, parameterize: [%{kind: :local}, %{kind: :memory}]

  alias Jido.Joi
  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Scenarios}

  setup context do
    test = self()

    commands = %{
      render: %{
        grant: :report,
        schema:
          Joi.object(%{path: Joi.string(), format: Joi.literal("upper")},
            unrecognized_keys: :error
          ),
        read: ["approved.txt"],
        run: fn %{path: path}, read ->
          send(test, {:dispatch, path})

          with {:ok, %{content: bytes}} <- read.(path),
               do: {:ok, %{content: String.upcase(bytes)}}
        end
      }
    }

    grants = [:open, :read, :close] ++ Map.get(context, :extra_grants, [:report])
    files = %{"approved.txt" => "release report", "private.txt" => "private notes"}

    binding =
      {BindingFixture, kind: context.kind, commands: commands, grants: grants, files: files}

    %{agent: agent} = Scenarios.prepare(context, AgentJobs.Work, [work: binding], context.kind)
    assert :commands in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
    %{agent: agent}
  end

  test "03.07 discovers the registered schema and renders a scoped report", %{agent: agent} do
    assert %{commands: [%{name: :render, schema: schema}]} =
             AgentJobs.succeeded(agent, :commands, %{realm: :work})

    assert inspect(schema) =~ "format"

    assert %{content: "RELEASE REPORT"} =
             AgentJobs.succeeded(agent, :invoke, request("approved.txt"))

    assert_receive {:dispatch, "approved.txt"}

    AgentJobs.rejected(agent, :invoke, :permission_denied, request("private.txt"))
    assert_receive {:dispatch, "private.txt"}
  end

  test "03.07 malformed arguments and unknown names fail before dispatch", %{agent: agent} do
    request = request("approved.txt")
    AgentJobs.rejected(agent, :invoke, :command_unavailable, %{request | command: :other})

    AgentJobs.rejected(
      agent,
      :invoke,
      :invalid_command_arguments,
      put_in(request.input.format, "html")
    )

    AgentJobs.rejected(
      agent,
      :invoke,
      :invalid_command_arguments,
      %{request | input: Map.put(request.input, :implementation, "other")}
    )

    refute_received {:dispatch, _}
  end

  @tag extra_grants: []
  test "03.07 an agent without the specific grant cannot discover or dispatch the command", %{
    agent: agent
  } do
    assert %{commands: []} = AgentJobs.succeeded(agent, :commands, %{realm: :work})
    AgentJobs.rejected(agent, :invoke, :permission_denied, request("approved.txt"))
    refute_received {:dispatch, _}
  end

  defp request(path), do: %{realm: :work, command: :render, input: %{path: path, format: "upper"}}
end
