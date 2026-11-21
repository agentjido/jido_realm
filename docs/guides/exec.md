# Exec

Declare the Realm with the `:program` Profile. The host supplies a runner
for each runtime and grants the agent access. After open, check that the
runtime appears in the effective capabilities.

## Run a file

Start a session with the following options. Bind it to `:work` as in
[First Realm](first-realm.md), with `:open`, `:close`, `:read`, `:write`,
and `:run` grants.

```elixir
alias Jido.Realm.{Placement, Runner, Session}

{:ok, session} =
  Session.start_link(
    provider: {Placement, :memory},
    runners: %{lua: {Runner.Lua, []}},
    max_run_ms: 2_000
  )
```

In a live action, open the Realm, save the entry point, and run it.

```elixir
alias Jido.Realm

{:ok, %{capabilities: capabilities}} = Realm.open(context, :work)
true = :lua in capabilities

{:ok, _} = Realm.file(context, :work, :create, "main.lua", ~S|print("Hello")|)

{:ok, %{status: :succeeded, output: output}} =
  Realm.exec(context, :work, {:entrypoint, :lua, "main.lua"}, timeout_ms: 1_000)
```

The result includes the run ID, status, exit code, combined output, and
published paths. Inspect the status even if the call returns `{:ok, result}`.
Use `args:` for literal arguments. Use `cwd:` for a working directory in
the Realm and `inputs:` to declare extra files for a runner that stages them.

Lua runs in a fresh VM and uses `realm.read` and `realm.write` for file
access. If evaluation succeeds, Realm publishes Lua drafts with revision
checks, one file at a time. Use `Jido.Realm.close/2` when work is complete.

## Run a named check

A named check lets the host select the check program and give the agent
permission to invoke it by name. This example uses a staged JavaScript
runner with a cached Node 22 image. Use an owned Local placement. Pass the
following `runners` and `commands` options to `Session.start_link/1`.

```elixir
adapter =
  {Jido.Realm.Runner.Docker,
   staged: [runtime: :javascript, image: "node:22-alpine", files: ["verify.ts"]]}

runners = %{javascript: adapter}
commands = %{
  verify: %{
    grant: :verify,
    schema: Jido.Joi.object(%{}),
    exec: {:check, :javascript, "verify.ts"},
    options: [timeout_ms: 15_000]
  }
}
```

Give the binding `:read`, `:run`, and `:verify` to run the check, and
`:write` to save its file. Open the Realm before you run these calls in an
action. The sample script confirms that the runner can start Node. For
your own project, make the check verify the behavior your service needs.

```elixir
alias Jido.Realm

{:ok, _} =
  Realm.file(context, :work, :create, "verify.ts", ~S|console.log("Check passed");|)

{:ok, %{status: :succeeded, id: check_id, source_ref: source_ref}} =
  Realm.exec(context, :work, {:command, :verify, %{}}, request_id: "verify-1")

{:ok, %{status: :succeeded}} = Realm.run_status(context, :work, check_id)
```

`Jido.Realm.commands/2` lists the commands and input schemas available to
the binding. To run a new check after a source edit, use a new request ID.
Within the same session, replaying the same request ID and request returns
the recorded result. A changed request with the same ID returns
`:request_conflict`. Use `mode: :background` only when the runner and
Profile supply background execution. Use `Jido.Realm.run_status/3` to read
progress or the final result.

Use `{:shell, :bash, command}` only if the host enables `coding: [bash: true]`
and supplies a runner with Bash command support. If a run returns
`{:error, {:unknown, id}}`, the host must confirm cleanup before the
session can release its placement.
