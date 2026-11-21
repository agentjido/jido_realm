defmodule Jido.Realm.Integration.TreeTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files}

  realm_case "01.01 organize a directory and keep an occupied destination",
    agent: AgentJobs.Work,
    cases: [
      local: [work: {BindingFixture, kind: :local}],
      memory: [work: {BindingFixture, kind: :memory}]
    ] do
    %{agent: agent, observe: %{work: read}} ->
      assert :tree in AgentJobs.succeeded(agent, :open, %{realm: :work}).capabilities
      realm = %{realm: :work}

      Files.assert_rejected(
        agent,
        :create,
        "project/draft",
        :not_found,
        Map.put(realm, :content, "rough")
      )

      Files.assert_reply(agent, :mkdir, "project", realm)
      Files.assert_reply(agent, :create, "project/draft", Map.put(realm, :content, "rough"))
      Files.assert_reply(agent, :create, "project/existing", Map.put(realm, :content, "keep"))
      Files.assert_reply(agent, :edit, "project/draft", Map.put(realm, :content, "revised"))

      Files.assert_rejected(
        agent,
        :rename,
        "project/draft",
        :already_exists,
        Map.put(realm, :destination, "project/existing")
      )

      assert read.("project/draft") == {:ok, "revised"}
      assert read.("project/existing") == {:ok, "keep"}

      Files.assert_reply(
        agent,
        :rename,
        "project/draft",
        Map.put(realm, :destination, "project/final")
      )

      Files.assert_reply(agent, :delete, "project/existing", realm)

      Files.assert_reply(agent, :list, "project", realm, %{
        entries: [%{path: "project/final", type: :file}]
      })

      assert read.("project/final") == {:ok, "revised"}
      assert read.("project/draft") == {:error, :not_found}
      assert read.("project/existing") == {:error, :not_found}
      AgentJobs.succeeded(agent, :close, realm)
  end
end
