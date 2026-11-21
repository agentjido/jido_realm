defmodule Jido.Realm.Integration.AuthorizationTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}

  defp record(owner) do
    fn op, path, _, run ->
      send(owner, {:dispatched, op, path})
      run.()
    end
  end

  realm_case "02.01 check the caller before dispatching file or copy operations",
    agent: AgentJobs.Pair,
    cases: [
      local: [
        source: {BindingFixture, kind: :memory, mode: :static, hook: record(self())},
        target: {BindingFixture, kind: :local, mode: :static, hook: record(self())}
      ],
      memory: [
        source: {BindingFixture, kind: :local, mode: :static, hook: record(self())},
        target: {BindingFixture, kind: :memory, mode: :static, hook: record(self())}
      ]
    ] do
    %{
      agent: writer,
      instance: instance,
      bindings: bindings,
      placements: %{source: source, target: target}
    } ->
      target.seed.("note", "original")
      source.seed.("draft", "may copy")
      reader_bindings = Map.update!(bindings, :target, &Keyword.put(&1, :grants, [:read]))
      reader = Scenarios.start_agent(instance, AgentJobs.Pair, reader_bindings)

      Files.assert_reply(reader, :read, "note", %{realm: :target}, %{content: "original"})
      assert_receive {:dispatched, :read, "note"}

      for op <- [:create, :edit, :delete] do
        Files.assert_rejected(reader, op, "note", :permission_denied, %{
          realm: :target,
          content: "denied"
        })
      end

      AgentJobs.rejected(reader, :copy, :permission_denied, %{path: "draft", to: "denied"})
      refute_received {:dispatched, _, _}
      assert target.observe.("note") == {:ok, "original"}
      assert target.observe.("denied") == {:error, :not_found}

      Files.assert_reply(writer, :edit, "note", %{realm: :target, content: "approved"})
      assert_receive {:dispatched, :edit, "note"}
      assert target.observe.("note") == {:ok, "approved"}
  end
end
