# First Realm

A Realm gives a Jido agent a place to work. A Profile states which
capabilities the agent needs. The host selects the provider and grants
operations to the agent.

This example opens a managed Realm in Memory, writes a note, and closes
the Realm. From the package directory, run `mix deps.get`, then start
`iex -S mix`. Run the following blocks in that IEx session.

## Declare and bind the Realm

Declare `:work` with the built-in `:files` Profile. Start a session with
an owned Memory store and bind it to `:work`.

```elixir
defmodule RealmGuideAgent do
  use Jido.Agent, name: "realm_guide_agent", plugins: [Jido.Realm.Plugin]

  realms do
    realm :work, profile: :files
  end
end

{:ok, session} =
  Jido.Realm.Session.start_link(provider: {Jido.Realm.Placement, :memory})

bindings = %{work: [session: session, grants: [:open, :close, :read, :write]]}

{:ok, _} = Jido.start(name: RealmGuide)
{:ok, agent} =
  Jido.start_agent(RealmGuide, RealmGuideAgent,
    id: "realm-guide",
    plugin_runtime_options: [{Jido.Realm.Plugin, bindings: bindings}]
  )

:ok = Jido.AgentServer.await_ready(agent)
```

## Open, write, and close

Send Signals to the live agent. Include the Realm name in the Signal data.
Open returns the effective capabilities. Use these capabilities to decide
which optional operations to call.

```elixir
call = fn type, data ->
  signal = Jido.Signal.new!(type, Map.put(data, :realm, :work), source: "/realm-guide")
  Jido.AgentServer.call(agent, signal)
end

{:ok, %{status: :committed, reply: %{data: %{capabilities: capabilities}}}} =
  call.("realm.open", %{})

true = :files in capabilities

{:ok, %{status: :committed}} =
  call.("realm.file.create", %{path: "notes.txt", content: "Hello"})

{:ok, %{status: :committed, reply: %{data: %{content: "Hello"}}}} =
  call.("realm.file.read", %{path: "notes.txt"})

{:ok, %{status: :committed}} = call.("realm.close", %{})
```

Close releases the owned Memory store and removes its contents. Start a
new session to open a new managed Realm. To keep files across sessions,
use a borrowed store or a host-owned directory. See [Providers](providers.md).

In a live Jido action, use the action's `context` with `Jido.Realm.open/2`,
`Jido.Realm.file/5`, and `Jido.Realm.close/2`. The remaining guides use
that context for operations in an action.
