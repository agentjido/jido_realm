# Jido Realm

Jido Realm gives an agent a place to work. The host binds a file backend when
it starts the agent. The agent uses the same file Signals for each binding.

Use the [host API](HOST.md) to provision a Realm, recover commands, and deploy
a saved result. Realm uses [Jido Shell](https://github.com/agentjido/jido_shell)
for shell sessions and [Jido VFS](https://github.com/agentjido/jido_vfs) for
filesystems. They start as separate OTP applications.
See [local installation](HOST.md#use-from-another-project) and the
[example commands](examples/README.md#run-the-example-suites).

```elixir
defmodule MyFileAgent do
  use Jido.Agent, name: "my_file_agent", plugins: [Jido.Realm.Plugin]

  realms do
    realm :work, profile: :files
  end
end

root = Path.expand("realm-demo")
File.mkdir_p!(root)
{:ok, _} = Jido.start(name: RealmDemo)

{:ok, server} =
  Jido.start_agent(RealmDemo, MyFileAgent,
    id: "files",
    plugin_runtime_options: [{Jido.Realm.Plugin, bindings: %{work: [root: root]}}]
  )

:ok = Jido.AgentServer.await_ready(server)

signal =
  Jido.Signal.new!(
    "realm.file.create",
    %{realm: :work, path: "notes.txt", content: "Hello"},
    source: "/demo"
  )

{:ok, %{status: :committed, reply: %{data: %{operation: :create, path: "notes.txt"}}}} =
  Jido.AgentServer.call(server, signal)
```

| Signal | Data | Behavior |
| --- | --- | --- |
| `realm.file.create` | `path`, `content` | Creates a new file. Fails if the path exists. |
| `realm.file.read` | `path` | Returns the file text in `content`. |
| `realm.file.edit` | `path`, `content` | Replaces an existing file's text. |
| `realm.file.delete` | `path` | Removes an existing file. |

For a named Realm, include `realm` in the Signal data. An agent action can
also call `Jido.Realm.file(context, :work, :read, "notes.txt")`. Agents with
one unnamed Realm can still bind `root:` or `backend:` directly and omit
`realm` from their Signals.

For managed work, the host can bind `session: pid` to a
`Jido.Realm.Session` and grant operations. The agent opens and closes
that session through `Jido.Realm.open/2` and `Jido.Realm.close/2`.
The session checks the requirements named by the agent. Use the built-in
`:files` Profile or a module that implements `c:Jido.Realm.Profile.requirements/0`.
The host selects the provider and sets the permitted capabilities.
An optional session `owner: pid` starts the close process when that
owner exits.

Use relative paths, existing parent directories, and UTF-8 file contents.
Realm rejects empty path components, `.`, `..`, and names that start with
`.jido-realm-`. Local also rejects symlinks. Use a host-controlled Local tree
on a POSIX filesystem. Keep other processes from changing directories or
links during a Realm operation.

A committed file operation returns `realm.file.result`. Its data includes
`operation` and `path`. A read also returns `content`. A file failure returns
a failed Jido turn with `error.details.code` set to `:realm_file_error`.
Its `reason` describes the failure, for example `:already_exists`, `:not_found`,
or `:invalid_path`.

For Memory, start a store with `Jido.Realm.Memory.start_link/1` and use
`[backend: {Jido.Realm.Memory, store}]` as the binding for `:work`.
A Memory store starts with one empty root directory.
Its contents last for the life of the store process. File changes occur inside
the Jido action and can survive a later turn failure.

## Check host and test prerequisites

After `mix deps.get` and `mix compile`, run the doctor from the package root.

```sh
mix jido_realm.doctor
mix jido_realm.doctor --lane docker --format json --strict
```

Select `core`, `native`, `docker`, `browser`, `apple_container`, `sprites`,
`live_sprite`, or `lmstudio` with `--lane`. The default report includes all
lanes. Use `--strict` in CI to fail when a selected lane needs attention.

The doctor checks local prerequisites. For example, it checks Docker Engine
and the cached test images, and checks whether the Sprite test token is set
without printing its value. It does not authenticate with Sprites or verify
which model is loaded in LM Studio. Run the matching integration lane for
provider evidence. [Integration ladder](test/integration/README.md) ·
[Production delivery plan](docs/plans/realm-production-delivery.md)

## Attach a VFS store

Pass a running Jido VFS filesystem to the session. The VFS Memory adapter
supports atomic captures and checked edits. Realm uses them to check each
create, edit, and delete against the current file tree. The host owns the
store and can use it again after the Realm closes.

```elixir
alias Jido.Realm.{Provider, Session}
alias Jido.VFS.Adapter.InMemory

filesystem = InMemory.configure(name: :realm_files)
{:ok, _store} = InMemory.start_link(filesystem)
{:ok, session} = Session.start_link(provider: {Provider.VFS, filesystem})
```

Bind `[session: session]` to the agent's Realm. The VFS provider offers
the basic file capability. It requires `capture/1` and `apply_edits/3`,
which require a VFS revision with atomic capture support.

## Use a Fly.io Sprite

Create a client with the [Fly.io Elixir SDK](https://hex.pm/packages/sprites)
and pass it to the Sprite provider. Use `:borrowed` to keep an existing
Sprite after close. Use `:owned` with an unused name to create a Sprite and
delete it on close.

```elixir
alias Jido.Realm.{Provider, Session}

{:ok, session} =
  Session.start_link(
    provider: {Provider.Sprite,
      %{
        mode: :borrowed,
        client: Sprites.new(System.fetch_env!("SPRITES_TOKEN")),
        name: "report-review",
        root: "/home/sprite",
        readable: ["report.html"]
      }}
  )
```

The host selects a trusted Sprite and an absolute root. The agent can read
only the exact relative paths in `readable`. Keep those paths on the trusted
tree, including any symlink targets. The default suite uses a controlled
transport. The [Sprite lifecycle case](test/integration/06_provider_lifecycle/06_04_allocate_or_reuse_a_sprite/README.md)
also has a live test for a dedicated test account.

## Run a program

Declare a managed Realm with the `:program` Profile. The host chooses the
runners available in the session. A custom Profile can require a specific
runtime, such as `:lua`, to make open fail if that runtime is unavailable.

```elixir
realms do
  realm :work, profile: :program
end

# Host configuration. Bind the session to :work when starting the agent.
{:ok, session} =
  Jido.Realm.Session.start_link(
    provider: {Jido.Realm.Placement, :memory},
    runners: %{lua: {Jido.Realm.Runner.Lua, []}},
    max_run_ms: 2_000
  )

bindings = %{work: [session: session, grants: [:open, :close, :read, :write, :run]]}
```

In a live Jido action, open the Realm, save the entry point through the file
API, then run it. An agent can also send `realm.program.run` with the same
fields.

```elixir
Jido.Realm.exec(context, :work, {:entrypoint, :lua, "main.lua"},
  cwd: "project",
  inputs: ["helper.lua", "data.txt"],
  args: ["a literal argument"],
  timeout_ms: 1_000
)
```

To require specific controls, declare them for the runtime in a custom
Profile. For example, this Profile requires JavaScript with read-only
inputs, private scratch space, loopback-only networking, and a non-root
user.

```elixir
%Jido.Realm.Profile{
  required: [:files, :javascript],
  execution_controls: %{
    javascript: [:read_only_inputs, :private_scratch, :loopback_only, :non_root]
  }
}
```

Open fails if the host binding cannot supply a JavaScript runner with
those controls. A Local file tree can supply the inputs to that runner.

A terminal result contains `id`, `runtime`, `status`, `exit_code`, combined
`output`, `truncated`, and `published`. A program that exits with a
nonzero status returns `:failed` with its diagnostics. An unconfirmed run
returns `{:error, {:unknown, id}}`. The session denies further work and
requires host recovery before it can release that lease.

| Runtime | File visibility | Execution |
| --- | --- | --- |
| Lua | Mediated reads. Writes publish per file after evaluation succeeds, with revision checks. | A fresh Lua VM in a bounded BEAM process. |
| Bash, Python, JavaScript | The entry point and declared inputs are read-only in the container. The program can use private scratch space. The agent can save returned output through the file API. | A fresh Docker container with networking disabled by default and a host-selected cached image. |

Use `{Jido.Realm.Runner.Docker, image: image, context: context}` for Docker
runners. The host approves the image and Docker context. Each run executes
a fixed interpreter with literal arguments. Use images with the expected
interpreter path or set the host option `:binary`. See
[Program execution](test/integration/03_program_execution/README.md) for
the tested images, limits, and commands.

### Run a coding agent in Memory

Declare `realm :work, profile: :program` in the agent's `realms` block. The
host can bind it to one Memory session for all four runtimes.

```elixir
alias Jido.Realm.{Artifacts, Placement, Runner, Session}

{:ok, session} =
  Session.start_link(
    provider: {Placement, :memory},
    runners: %{
      lua: {Runner.Lua, []},
      bash: {Runner.Docker, image: "bash:5.2", workspace: :memory},
      python: {Runner.Docker, image: "python:3.13-alpine", workspace: :memory},
      javascript: {Runner.Docker, image: "node:22-alpine", workspace: :memory}
    }
  )

{:ok, store} = Artifacts.start_link(viewers: [:reviewer])

bindings = %{
  work: [session: session, presenter: {Artifacts, store},
         grants: [:open, :close, :read, :write, :run, :publish]]
}

# Pass [bindings: bindings] as the runtime options for Jido.Realm.Plugin.
```

| Signal | Data in addition to `realm: :work` | Reply |
| --- | --- | --- |
| `realm.open` | None | `realm.opened` with the effective capabilities |
| `realm.file.create` | `path` and `content` | `realm.file.result` |
| `realm.program.run` | `runtime`, `entrypoint`, optional `cwd`, `inputs`, `outputs`, `args`, and `timeout_ms` | `realm.program.result` |
| `realm.artifact.publish` | `entrypoint` and `paths` | `realm.artifact.published` with the saved version |
| `realm.close` | None | `realm.closed` |

The Docker Memory mode needs a trusted Docker context and a cached Linux
image with `/bin/sh`, `mkdir`, `base64` and `realpath`. It streams the
entry point and declared inputs into a fresh 16 MiB tmpfs at `/workspace`.
The input limit is 1 MiB per run. The program can read and write that tree.
Declare the UTF-8 output paths that Realm must save, up to 1 MiB of output
files per run. Interpret paths relative to the run's `cwd`. Create their
parent directories in Realm first. Include an existing file in both
`inputs` and `outputs` to update its contents.

Realm checks all returned files before it saves them. It checks the original
revision at each write. A failed write returns `:publication_failed` and
lists the paths that Realm already saved. A failed program saves no outputs.
Lua uses `realm.read` and `realm.write` inside the BEAM. An owned Memory
placement lasts until its session closes. The published bundles have their
own retention period in the presenter. Docker keeps its normal image and
container metadata on the engine.

Set `:private_network` on the Docker runner to select a host-approved
internal bridge network. Realm verifies the network and pins its ID. The
runner reports `:private_network` for that configuration and
`:loopback_only` for the default configuration.

Use `mode: :background` with a runner that reports bounded progress.
`Realm.run_status/3` returns the current progress or terminal result.

```elixir
{:ok, %{id: id}} =
  Jido.Realm.exec(context, :work, {:entrypoint, :lua, "check.lua"}, mode: :background)

Jido.Realm.run_status(context, :work, id)
```

The host registers named commands with a schema and a grant.
`Realm.commands/2` lists commands for the caller's grants. A guest command
runs a host-configured script or entry point. A trusted host callback receives
the input and a reader limited to its approved paths. Its return value is
in the result's `:value` field.

Call `Realm.exec/4` with `:request_id` to recover a lost reply. Reuse the
same request and mode. A different request with the same ID returns
`:request_conflict`. A session retains explicit IDs and check results
until close, subject to the host's `:max_requests` limit (default 128).
On an `:unknown` result, the session owner can use
`Jido.Realm.Session.reconcile_run/2` where the runner can confirm cleanup.

### Run a coding agent in a container

Register the actions from `Jido.Realm.Coding.file_actions/0` for a Local or
Memory Realm. Use `read` to get a revision for `edit`. The same action can
read a group of files. `write` creates a file and returns its revision.
Use `glob` for file names and `grep` for matching lines.

For a staged Local workspace, select
`{Jido.Realm.Runner.Docker, staged: options}` or
`{Jido.Realm.Runner.AppleContainer, options}`. Set `:image` and the
`:files` or `:directories` to stage. Each guest gets a read-only snapshot
and private scratch space. The host can configure the runtime binary,
flags, environment, toolchain probe, and check exit codes. Set `grep: true`
to check for native ripgrep and make it available in the Bash guest.

Set `coding: [bash: true]` to allow
`Realm.exec(context, :work, {:shell, :bash, "rg TODO lib"})` or the
`Jido.Realm.Coding.Bash` action. Grant `:read` and `:run` to that binding.
A host-approved check can use a Bash command or a program entry point.

```elixir
commands = %{
  verify: %{
    grant: :run,
    schema: Jido.Joi.object(%{}),
    exec: {:check, :bash, "mix test"}
  }
}

{:ok, %{status: :succeeded, id: check_id}} =
  Jido.Realm.exec(context, :work, {:command, :verify, %{}}, request_id: "check-1")
```

See the [Phoenix and LM Studio example](test/integration/09_model_driven_files/README.md)
for a host configuration that supplies the Mix dependencies offline.
The existing entry point, `start_run`, `invoke`, and `coding_run` calls
use the same execution path.

## Publish a saved HTML artifact

The host can give a named Realm a presenter. This example uses a bounded
in-memory presenter with a one-hour retention period. Set viewer identities
when you start the presenter. An agent needs `:read` and `:publish` grants.

```elixir
alias Jido.Realm.Artifacts

{:ok, store} = Artifacts.start_link(viewers: [:reviewer], retention_ms: 3_600_000)

bindings = %{
  work: [session: session, presenter: {Artifacts, store},
         grants: [:open, :close, :read, :write, :publish]]
}

# In an agent action with the Realm open:
{:ok, artifact} =
  Jido.Realm.publish_artifact(context, :work, "index.html", ["index.html", "report.js"])

# In the host, after authenticating the reviewer:
{:ok, %{content: html, headers: headers}} = Artifacts.read(store, :reviewer, artifact.id)
```

Serve the selected files at relative paths on a dedicated artifact origin.
Apply the returned headers. Authorize each request, including requests for
styles and scripts. The published version survives Realm close for the
retention period while its presenter is running. Use `Artifacts.revoke/2`
to end access sooner. A host can implement `Artifacts.publish/3` as a
behavior callback for another store. Each bundle can contain up to 32 UTF-8
HTML, CSS, JavaScript, JSON, and text files with a total size of 1 MiB.

## Run a service and expose a port

Register the service and its HTTP port on the session. Configure the adapter
with `:preview`, the gateway URL with `:preview_base_url`, and the viewer
identities with `:preview_viewers`. The `:program` Profile can admit
`:services` and `:ports`.

```elixir
services = %{
  app: %{
    exec: {:shell, :bash, "mix run --no-halt"},
    ports: %{http: 8080},
    require_check: :verify
  }
}

# In the agent action, after :verify succeeds:
{:ok, service} = Jido.Realm.start_service(context, :work, :app, verified_by: check_id)
{:ok, endpoint} = Jido.Realm.expose_port(context, :work, service.id, :http)
:ok = Jido.Realm.close_port(context, :work, endpoint.id)
:ok = Jido.Realm.stop_service(context, :work, service.id)
```

Starting a service requires `:read`, `:run`, and `:service`. Stopping it
requires `:service`. Opening or closing a route requires `:expose`. The
host can also allow a public route with `:publish_preview` and a bounded
`:ttl_ms` on `expose_port/5`. The gateway uses `Preview.target/3` or
`Preview.public_target/2` to resolve each request.

The adapter checks HTTP readiness before returning a service ID. A staged
adapter checks that the source and toolchain still match the successful
check. The service starts without a gateway route. It can keep running
after a route closes. Stopping the service or closing the Realm revokes all
its routes. The current adapters support one running service and one
configured HTTP port per session. A container adapter can reserve loopback
transport at startup. The gateway controls access to that transport.

The existing preview calls still start a service and return its route in
one step.

### Trusted native services

Realm depends on [erlexec](https://hexdocs.pm/erlexec/readme.html) for native
service supervision. Its helper requires a C++ toolchain at build time. Run the
host application as a non-root user with `SHELL` set, for example to `/bin/sh`.

Pass these options to `Jido.Realm.Session.start_link/1` with the provider
configuration.

```elixir
preview_options = [
  preview: {:native,
    name: "report",
    command: ["/opt/report/bin/server"],
    cwd: "/opt/report",
    port: 18_080},
  preview_base_url: "https://review.example.org/preview",
  preview_viewers: [:reviewer]
]

# In an agent action with the Realm open
{:ok, preview} = Jido.Realm.start_preview(context, :work, :native, "report")
```

Reserve the port for this service. The executable, its scripts, and its
configuration must come from a trusted host location outside agent-writable
directories. The command runs with the host user's privileges. It receives
`HOST=127.0.0.1` and the configured `PORT` in a clean environment. The
executable must honor those values and keep its children in its process group.
The agent selects the configured name and can set a startup timeout.

Realm waits for an HTTP success response at `/` before it returns the URL.
It denies route lookups when the managed process exits. A stop or close checks
that the process group has gone before Realm releases the placement. If cleanup
is unconfirmed, Realm keeps the lease and blocks new work. After the group
stops, retry close.

### Sandboxed applications

For Docker, the host selects a cached image, a runtime, and a network.

```elixir
preview_options = [
  preview: {Jido.Realm.Runner.Docker,
    runtime: :python, runner: [image: "python:3.13-alpine"], network: "bridge"},
  preview_base_url: "https://review.example.org/preview",
  preview_viewers: [:reviewer]
]
```

Use `Realm.start_preview/5` with the language runtime and entry point. The
Docker adapter supplies `PORT` and waits for a successful HTTP response at
`/`.

### Gateway access

The gateway authenticates each viewer before it calls
`Jido.Realm.Preview.target/3`. Forward the request only when Realm returns a
target. `Realm.stop_preview/3` or Realm close revokes access and stops the
service.

For temporary anonymous access, set `:preview_public_base_url` to a separate
HTTPS route and set `:preview_max_public_ms`. An agent with the additional
`:publish_preview` grant can call `Realm.share_preview/4` and
`Realm.unshare_preview/3`. The gateway uses `Jido.Realm.Preview.public_target/2`
for the public HTTPS route. That lookup checks the expiry on every request.

## Run the integration ladder

```sh
mix test test/integration
```

The [integration ladder](test/integration/README.md) covers named Realms,
file and transfer contracts, and policy checks. Its `realm_case` macro runs
each agent job using the named bindings for that case.

## Code layout

| Code | Responsibility |
| --- | --- |
| [Realm](lib/jido_realm.ex) | Agent calls, grants, and transfer between Realms. |
| [Plugin](lib/jido_realm/plugin.ex) and [FileAction](lib/jido_realm/file_action.ex) | Agent declarations, host binding, and Jido Signal input and replies. |
| [Profile](lib/jido_realm/profile.ex), [Session](lib/jido_realm/session.ex), and [Provider](lib/jido_realm/provider.ex) | Required capabilities, open and close, and provider leases. |
| [VFS and Sprite providers](lib/jido_realm/provider) | Borrow a VFS store, or attach to or allocate a Sprite. |
| [Files](lib/jido_realm/files.ex) and [file backends](lib/jido_realm/files) | File operation validation, normalized results, and storage. |
| [Runner](lib/jido_realm/runner.ex), [RunAction](lib/jido_realm/run_action.ex), and [execution adapters](lib/jido_realm/runner) | Program requests, limits, diagnostics, and runtime bindings. |
| [Artifacts](lib/jido_realm/artifacts.ex) | Bundle validation, saved versions, viewer access, and retention. |
| [Preview](lib/jido_realm/preview.ex) | Adapter contract and route lookup for the host gateway. |
| [Conformance support](test/support/conformance) | Test agents, host bindings, fault controls, and direct observers. |

See the [conformance hardening scope](docs/plans/realm-case-hardening.md)
for the file contracts tested before program execution.

## Run the basic file conformance suite

```sh
mix test --only realm_file_contract --trace
```

Both bindings run the same exercises through a live Jido agent. To add a
binding, register a fixture in the test module.

```elixir
use Jido.Realm.Conformance.Files,
  bindings: [local: LocalFixture, memory: MemoryFixture]
```

A fixture implements `prepare(context)` and supplies four things.

| Responsibility | Local | Memory |
| --- | --- | --- |
| Provision an isolated store | Create a temp directory. | Start a fresh supervised store process. |
| Bind the agent to that store | Return `runtime_options: [root: root]`. | Return `runtime_options: [backend: {Memory, store}]`. |
| Observe the store directly | Return an `observe` function that reads with `File.read/1`. | Return an `observe` function that reads the store state. |
| Release the store | Register temp directory removal with `on_exit/1`. | Let ExUnit stop the supervised store. |

The observer returns `{:ok, bytes}` or `{:error, :not_found}` for a missing
file. The shared tests use Realm Signals to make all changes and use the
observer to check where those changes landed. The harness starts the same
agent for every binding.

## Run the example suite

```sh
mix test.realm --trace
```

The [example suite](examples/realm/README.md) starts with agent jobs for saving a
note and copying it between Realms. The Lua and Apple Container examples
provide runnable references for execution and service previews. The
[conformance map](docs/conformance-map.md) describes the underlying contracts.
