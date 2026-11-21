# Realm host API

Use `Jido.Realm.Host` from trusted code to manage working trees, command
execution, recovery, and deployment. Use `Jido.Realm` to grant agents access
to named Realms.

See the [Realm guides](docs/guides/table_of_contents.md) for the API,
runtime choices, and examples.

## Open one working tree

Set the named profiles in your host application's configuration. Choose a
directory that the host can write and keep across BEAM restarts.

```elixir
import Config

config :jido_realm,
  profiles: %{
    build: %{
      provider: :memory,
      policy: [:read, :write, :execute, :save],
      tools: ["cp"],
      store: "reports"
    },
    review: %{provider: :memory, policy: [:read, :import], store: "reports"}
  },
  stores: %{"reports" => Path.expand("../workspace-snapshots", __DIR__)}
```

```elixir
alias Jido.Realm.Host

{:ok, workspace} = Host.open(profile: :build)
:ok = Host.write(workspace, "reports/draft.txt", "hello\n")
{:ok, %{exit_status: 0}} =
  Host.run(workspace, ["cp", "draft.txt", "final.txt"], cwd: "reports")

{:ok, saved} = Host.save(workspace)
:ok = Host.close(workspace)

{:ok, review} = Host.open(profile: :review, from: saved)
{:ok, "hello\n"} = Host.read(review, "reports/final.txt")
:ok = Host.close(review)
```

The named profile selects a file tree and runner. File calls and commands
use the same tree. Keep the saved reference as JSON to reopen the files
in a new BEAM with access to the same store.

## File API

This example opens a workspace with the mount-based API. For a named profile,
use the relative-path workflow above.

```elixir
alias Jido.Realm.Host

{:ok, ws} = Host.open(policy: :workspace_write)
:ok = Host.mkdir(ws, "/src")
:ok = Host.write(ws, "/src/input.txt", "hello")
{:ok, "hello"} = Host.read(ws, "/src/input.txt")
:ok = Host.delete(ws, "/src/input.txt")
:ok = Host.close(ws)
:ok = Host.close(ws)
```

Keep the same handle after file changes. The controller owns mutable state and
checks policy. All host methods return structured errors
with a code, operation, resource ID, and bounded cause. Paths must be absolute
UTF-8 paths without NUL or parent traversal. Writes accept iodata. The caller
owns the handle unless the host sets `owner:`. Open resources before passing
them to short-lived Action tasks.

`list` returns Entry records with absolute paths. `info` returns current policy,
owner, and session status. `capture` returns immutable content and a revision.
Use `replace(ws, capture, expected: revision)` for checked replacement.
`run` returns an Execution record. Keep the same handle; it has no cached
session or command fields. `new`, `snapshot`, `restore`, and `execute` are removed.

`test/examples/workspace_file_api_test.exs` and `workspace_contract_test.exs`
run file, capture, command, session, and policy checks directly, through
`Jido.Exec`, and through a real AgentServer with
Jido Signals. Its Actions and Signal adapter remain test-only. No model is used.

## Internal boundaries

| Module | Responsibility |
| --- | --- |
| `Jido.Realm.Host` | Working trees, commands, and saved snapshots |
| Jido.Realm.Host.Lifetime (internal) | Ownership of mounted storage and Shell sessions |
| `Jido.Realm.Host.Sandbox` | Local processes, Docker/gVisor, Apple Container, files, and retained services |
| `Jido.Realm.Host.Deploy` | Targets, preparation plans, execution records, and recovery |
| `Jido.Realm.Host.Deploy.OTP` | OTP release handling and explicit state migration |
| `Jido.Realm.Host.Deploy.Source` | Source projection, activation, and service restart |
| `Jido.Realm.Host.Policy` | Permission checks used by Realm host controllers |
| `Jido.VFS` | Storage adapters and atomic file captures |
| `Jido.Shell` | Shell sessions and command execution |

The `:jido_realm` OTP application starts the Realm registries and
supervisors. Shell and VFS start through their own OTP applications. The
target-side deployment module is in `src/`.
See the [VFS guide](https://github.com/agentjido/jido_vfs) and
[Shell guide](https://github.com/agentjido/jido_shell).

A named profile binds one tree to a runner. When you use the lower-level
Sandbox API directly, it manages its own tree. Deploy uses a Sandbox target.
A deployment `Snapshot` is a file payload with a digest and a caller-supplied
source ID. It does not own branches, commits, merges, or source history.
`Deploy.Snapshot.from_capture/2` converts a fixed VFS capture into that payload.
Later live edits do not change the payload. See [memory capture deployment](DEPLOY.md#vfs-memory-captures).

## Target and file boundaries

Deploy resolves every target through Sandbox before it connects. Target identity
uses the controller-owned Sandbox ID and a canonical relative path. Dot paths,
trailing separators, and case aliases on a case-insensitive filesystem cannot
create a second deployment controller. Symlink traversal is refused. Concurrent
connections use the same registry key. This is one-controller protection within
one Realm application. It is not a distributed deployment lock.

Deploy sends target reads, writes, directory creation, file checks, link
activation, and OTP release-file setup through Sandbox. The local provider owns
those OS calls. `Snapshot.from_directory/2` and `Snapshot.verify/2` remain explicit
host-side import and check helpers. They are not used to inspect deployed files.
No remote provider is added by this change.

## Command file views

A `Jido.Realm.Host.FileView` names the file source, owner, path, and observed
revision. Mounted file views describe mounted VFS files. Sandbox views describe a
directory in that environment. The two kinds cannot be substituted.

```elixir
{:ok, workspace} = Jido.Realm.Host.open()
:ok = Jido.Realm.Host.write(workspace, "/input", "draft")
{:ok, view} = Jido.Realm.Host.file_view(workspace)
{:ok, record} = Jido.Realm.Host.run(workspace, "cat /input", files: view)
"draft" = record.output
^view = record.files
:ok = Jido.Realm.Host.close(workspace)

{:ok, sandbox} = Jido.Realm.Host.Sandbox.open()
:ok = Jido.Realm.Host.Sandbox.write(sandbox, "input", "draft")
{:ok, view} = Jido.Realm.Host.Sandbox.file_view(sandbox)
{:ok, result} = Jido.Realm.Host.Sandbox.exec(sandbox, "/bin/cat", ["input"], files: view)
^view = result.files
:ok = Jido.Realm.Host.Sandbox.destroy(sandbox)
```

The `:files` option accepts a view or `:current` (the default).
A stale view is refused before the command or service starts. Sandbox services
record the input view in their status. Deploy command evidence includes these
records. Sandbox revisions hash file contents and executable modes; directory
names and symlink destinations are also included. Links are recorded without
following them. This is a full directory scan for each command start.

`Host.run/3` returns `{:ok, %Execution{}}`, including `files` and
`after_files`, combined `output`, `exit_status`, `status`, `truncated`, and
`duration_ms`. Nonzero exits remain successful observations. Timeouts return
status `:timed_out` and cancel the command. Options use `timeout_ms:` and
`output_limit:`. A final file observation error stays in `after_files`.

VFS adapters that do not supply a capture revision, and workspaces with multiple
mounts, report `revision: :unavailable`. A named view with that revision is
refused with `:unversioned_file_view`. Commands can still use `files: :current`.

These revisions are pre-start observations and checks. They do not lock files or
make a command's file view immutable. Another process or a raw file handle can
change files during execution. There is no automatic synchronization between
memory files and Sandbox files. Use a projected, isolated tree when execution
must use fixed content.

## Policy

Set policy in the host profile for a named workspace. See
`Jido.Realm.Host.Profile` for grants, tool controls, and provider requirements.
For the mount-based host interface and direct Sandbox APIs below, set `policy:`
at open. The controller keeps it for its lifetime.

| Profile | Read and capture | File changes | Raw VFS or Shell handle | OS execution and deployment |
| --- | --- | --- | --- | --- |
| `:read_only` | Allow | Deny | Deny | Deny |
| `:workspace_write` | Allow | Allow | Deny | Deny |
| `:full_access` | Allow | Allow | Allow | Allow |

The default is `:full_access`. This keeps the current local access rules.
A host that exposes tools to an agent must select the
required profile explicitly.

```elixir
{:ok, workspace} = Jido.Realm.Host.open(policy: :workspace_write)
:ok = Jido.Realm.Host.write(workspace, "/notes.txt", "draft")
{:error, %Jido.Realm.Host.Error{code: :policy_denied}} = Jido.Realm.Host.run(workspace, "pwd")
:ok = Jido.Realm.Host.close(workspace)

{:ok, environment} = Jido.Realm.Host.Sandbox.open(policy: :full_access)
{:ok, result} = Jido.Realm.Host.Sandbox.exec(environment, "/bin/echo", ["ready"])
"ready\n" = result.output
:ok = Jido.Realm.Host.Sandbox.destroy(environment)
```

Restricted presets in this example refuse all Shell execution. This prevents a command from
bypassing file permissions. There is no command approval queue or policy editor
in this spike. Resource close and environment destroy remain available for
cleanup under every profile.

These checks apply to supported host calls from trusted host code. They are
not a security boundary against code in the controller VM. Direct calls to VFS,
Shell, File, or OTP can bypass them. A raw path is for trusted host integration.
The local provider runs under the current OS user. It cannot restrict child
process access to host files or the network. Use an isolated provider before
running untrusted code.

## Migration from the local spikes

| Previous module | Current module |
| --- | --- |
| `Jido.Sandbox` | `Jido.Realm.Host.Sandbox` |
| `Jido.Deploy` | `Jido.Realm.Host.Deploy` |
| `Jido.Deploy.OTP` | `Jido.Realm.Host.Deploy.OTP` |
| `Jido.Deploy.Source` | `Jido.Realm.Host.Deploy.Source` |

The separate `:jido_sandbox` and `:jido_deploy` applications are removed. Their
nested modules use the same namespace change. There are no compatibility aliases.
File changes and close now return `:ok`. Update callers that expect a returned
host handle. File errors now use `Jido.Realm.Host.Error`.

See [Sandbox](SANDBOX.md) for service ownership and provider limits.
See [Deploy](DEPLOY.md) for OTP migration, failure recovery, and Node.js
source deployment. OTP migration uses the current target state. A failed OTP
migration can restart the target and lose in-memory state.

## Checks

Run these commands from this folder:

```sh
mix deps.get
mix test
mix test.integration
mix format --check-formatted
mix compile --warnings-as-errors
```

The integration alias starts a separate BEAM instance for each example file.
The tests retain the Sandbox and Deploy scenarios and the host
scenarios. Policy tests check file changes, raw handles, execution, deployment,
and modified environment handles.

See [source provenance](docs/source-imports.md) and [LICENSE](LICENSE).

Command file views follow the active Shell backend. The built-in virtual backend
uses the VFS revision. Other backends report `kind: :backend`, the
backend module and session PID as owner, `path: :unknown`, and
`revision: :unavailable`. A local VFS revision cannot prove the state of remote
files. These backends accept `files: :current` and refuse pinned file views.

## Use from another project

Install Realm from GitHub:

```elixir
{:jido_realm, github: "agentjido/jido_realm"}
```

For local development, point your application at the Realm checkout:

```elixir
{:jido_realm, path: "/path/to/checkout"}
```

Realm pins its Shell and VFS dependencies to Git revisions. To develop
against local checkouts, set both absolute source paths before running Mix
in the consumer or Realm checkout:

```sh
export JIDO_SHELL_PATH=/path/to/jido_shell
export JIDO_VFS_PATH=/path/to/jido_vfs
mix deps.get
```

Configure GitHub adapter credentials under `:jido_vfs` and Shell guardrails
under `:jido_shell`. Configure Realm profiles and snapshot stores under
`:jido_realm`.

Before a runtime cutover, close existing placements and confirm the provider
released them. Run the Realm deployment target before connecting it to a
Realm host. Keep snapshot store names, roots, and provider IDs so saved
references resolve after the cutover.

See [Open one working tree](#open-one-working-tree) for snapshot setup.
