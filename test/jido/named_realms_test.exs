defmodule Jido.Realm.NamedRealmsTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios, only: [realm_case: 3]

  alias Jido.Realm.Conformance.{Files, LocalFixture, MemoryFixture}

  defmodule TwoRealmAgent do
    use Jido.Agent, name: "realm_two_file_agent", plugins: [Jido.Realm.Plugin]

    realms do
      realm(:source, profile: :files)
      realm(:target, profile: :files)
    end
  end

  realm_case "file Signals select a declared Realm",
    agent: TwoRealmAgent,
    cases: [local_and_memory: [source: LocalFixture, target: MemoryFixture]] do
    %{agent: agent, observe: %{source: source, target: target}} ->
      Files.assert_reply(agent, :create, "note.txt", %{realm: "source", content: "local"})
      Files.assert_reply(agent, :create, "note.txt", %{realm: :target, content: "memory"})

      Files.assert_rejected(agent, :create, "blocked.txt", :unknown_realm, %{
        realm: "unlisted",
        content: "denied"
      })

      assert source.("note.txt") == {:ok, "local"}
      assert target.("note.txt") == {:ok, "memory"}
      assert source.("blocked.txt") == {:error, :not_found}
      assert target.("blocked.txt") == {:error, :not_found}
  end
end
