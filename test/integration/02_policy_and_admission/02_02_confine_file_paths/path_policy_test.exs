defmodule Jido.Realm.Integration.PathPolicyTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files}

  realm_case "02.02 accept rooted paths and host-selected bindings",
    agent: AgentJobs.Work,
    cases: [
      local: [work: {BindingFixture, kind: :local, mode: :static}],
      memory: [work: {BindingFixture, kind: :memory, mode: :static}]
    ] do
    %{agent: agent, placements: %{work: work}} ->
      separate =
        BindingFixture.prepare(%{realm: :outside, fixture_options: [kind: :local, mode: :static]})

      separate.seed.("sentinel", "outside")

      for path <- [
            "../sentinel",
            separate.where.() <> "/sentinel",
            "a/../sentinel",
            ".jido-realm-internal"
          ] do
        Files.assert_rejected(agent, :read, path, :invalid_path, %{realm: :work})

        Files.assert_rejected(agent, :create, path, :invalid_path, %{
          realm: :work,
          content: "denied"
        })
      end

      for key <- [:root, :backend, :session, :grants] do
        data = Map.put(%{realm: :work, path: "injected", content: "denied"}, key, "outside")
        assert {:ok, %{status: :failed}} = Files.call(agent, :create, data)
        assert work.observe.("injected") == {:error, :not_found}
      end

      if is_binary(work.where.()) do
        File.ln_s!(separate.where.(), Path.join(work.where.(), "outside"))
        Files.assert_rejected(agent, :read, "outside/sentinel", :invalid_path, %{realm: :work})
        Files.assert_rejected(agent, :delete, "outside/sentinel", :invalid_path, %{realm: :work})
      end

      Files.assert_reply(agent, :create, "permitted", %{realm: :work, content: "inside"})
      Files.assert_reply(agent, :read, "permitted", %{realm: :work}, %{content: "inside"})
      assert work.observe.("permitted") == {:ok, "inside"}
      assert separate.observe.("sentinel") == {:ok, "outside"}
  end
end
