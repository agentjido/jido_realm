# Jido Realm

**Jido Realm gives an agent a place to work.**

A Realm has a file tree. With execution support, the agent can write a
program, prepare its environment, run it against that tree, inspect the
result, and revise the program. With service support, the agent can start
an application and give someone a URL to review it. The same agent
interface works when the host changes where that work runs.

## Reference agent

The reference Realm application is a coding agent. It opens a repository,
inspects and edits files, runs setup, builds and tests against the same
working tree, diagnoses failures, and returns a reviewable diff and test
results. The host supplies the checkout, selects the tools and grants,
and can give a reviewer access to the result. The coding agent decides
which change to make. Realm supplies the environment and its controls.

The agent can also turn its work into something a person can open.

| Result | What the person can open | What supplies it |
| --- | --- | --- |
| **Saved artifact** | A versioned HTML report, demo, or visualization, with its styles, scripts, and images. | The host presents an approved set of files from a Realm. Local and Memory can supply those files. The host sets access and retention for the published copy. |
| **Live preview** | A running app, with live data or reloads when the app supports them. | An execution binding runs the service. Private ingress gives reviewers access after the service is ready. The service and route have explicit lifetimes. |

The host application renders artifacts and opens previews from a result
reference. Realm checks which files or service the agent can expose and
reports their state. The host isolates generated HTML from its own UI
and credentials. A retained artifact remains openable when the work
session or preview ends. See the [composed agent jobs](test/integration/08_composed_jobs/README.md).

## Profile and Realm

A **Profile** is reusable configuration for a kind of place. Examples
include a file workspace, an isolated execution environment, and a
durable sandbox. A Profile declares its required and optional
capabilities, toolchains, security controls, and retention requirements.
Several agents can use the same Profile for different jobs.

A **Realm** is a specific place opened from a Profile. It has an
identity, a file tree, and a placement such as a directory, container,
or remote sandbox. Its available capabilities come from the Profile,
what the provider can enforce, and what the host grants. A durable Realm
can outlive the agent and be reopened by another authorized agent.

An agent names the Realms it needs in its DSL. The current file example
declares one named Realm. [Note agent](examples/realm/01_organize_a_note/example.ex)

```elixir
realms do
  realm :work, profile: :files
end
```

An agent can hold multiple Realms. A job can use `:source` for a local
checkout and `:preview` for a remote sandbox. Each operation identifies
its Realm. The host controls which Profiles the agent can open and how
many instances it can hold. Host code can also open a Realm and give an
agent access to it.

| Object | What it describes |
| --- | --- |
| **Profile and binding** | The Profile describes the kind of place. The host binding selects an approved provider, placement policy, credentials, and operating limits. A new Realm can use a different binding when it meets the same requirements. |
| **Realm and placement** | The Realm identifies the place to work. Its placement identifies the provider resource and file tree. Reopening a durable Realm resolves its saved placement. A change of placement requires an explicit restore or migration. |
| **Session** | An agent's current access to a Realm. A session has its own permissions and lifetime. |
| **Run, service, and route** | A run identifies one execution. A service has an assigned port and a readiness state. A route gives a caller access to the service and has its own lifetime. |
| **Setup recipe and snapshot** | A recipe describes how to prepare an environment. A snapshot identifies saved state that can be restored. |

## Normalized surfaces

The agent uses the same operations and result shapes across providers
that support a contract. It can inspect what is available on an opened
Realm. If a required capability or control is unavailable or unknown,
Realm rejects the binding before work starts. An operation distinguishes
success, denial, unsupported requests, conflicts, failure, and unknown
outcomes. When the provider can confirm a previously unknown outcome,
reconcile the original request without repeating its effects.

| Surface | What Realm should support |
| --- | --- |
| **Open and close** | Open a fresh Realm, attach to an approved resource, or reuse one from a pool. The provider performs allocation and reports the placement. When close begins, the session rejects new work. Confirm close after admitted work can no longer change the Realm and the provider has applied the release policy. |
| **Files** | Create, read, edit, and delete named files through scoped relative paths. The minimum writable contract preserves UTF-8 bytes exactly, rejects duplicate create, and reports a missing file on read, edit, or delete. A read-only grant permits reads and denies mutations. Binary files, directories and their parent rules, listing, metadata, rename, search, streaming, and revision checks have separate contracts. |
| **Transfer** | Copy between named Realms through the same file interface. Check read access on the source and write access on the destination. Preserve exact bytes and report destination conflicts. For a move, delete the source only after the destination is verified and the source version still matches. |
| **Execute** | Run agent-written or imported programs, build steps, and tests against the Realm tree. Normalize the entry point, arguments, working directory, run ID, exit status, and bounded diagnostics. Profiles can also offer background runs, streamed output, interactive input, and inspection, waiting, or cancellation. |
| **Named commands** | A host can expose an approved command with a stable name, an argument schema, and required grants. The agent discovers and calls the commands available in its session. Realm checks grants before it dispatches the command. |
| **Prepare and resume** | Run an agent-authored setup recipe within its grants. Check the result before reporting readiness. Profiles can reuse a prepared environment whose recipe, inputs, toolchain, and required policy match. A failed setup produces no reusable prepared state. An optional resume hook can prepare a retained environment for use again. |
| **Present an artifact** | Publish a version of selected Realm files under a host grant. Return a reference with media type and source revision or content identity. The host controls who can open it and how long it lasts. A file-only binding can supply the output. |
| **Serve and expose** | Start a program listening on an assigned port. Access is private by default. Return a private preview after a readiness check. A host grant can let an agent publish a temporary public HTTPS URL without asking again. The grant limits the service and lifetime. Expiry or revocation closes the public route while the service can continue privately. |
| **Retain and recover** | Reopen a durable Realm with its source, outputs, and setup recipe. Profiles can also preserve the prepared environment, save and restore snapshots, or recover an existing run. Process and URL lifetimes are explicit. A lost reply leaves an outcome unknown until reconciliation can confirm it. |
| **Authorize and observe** | Check host grants for file access, transfer, execution, services, and lifecycle operations. Enforce the required namespace, mount, credential, network, and resource limits in the provider. Expose status and diagnostics with enough context to inspect a run or recover from an interruption. |

An agent can save an entry point, helper files, and inputs through Realm,
run them against the working tree, and read the result through Realm. A
provider can share the tree, mount it, or stage a copy. The Profile states
when changes become visible to the program and to other readers. A staged
run sees its own writes. It publishes after successful execution and
checks for newer versions. The binding states whether publication is
per file or atomic across the change set and reports partial publication.

The untrusted-code boundary applies to setup, builds, tests, dependency
hooks, and subprocesses. The host controls access to mounts, secrets,
inbound routes, and outbound network destinations. Provider credentials
stay with the host and provider. Profiles declare the
limits they require for time, resources, and output. When Realm confirms
that a run stopped, the run can no longer change files or serve traffic.
Writer takeover waits until the previous session and its running writers
can no longer write. If the binding promises exclusive write access, the
provider also accounts for external writers such as a maintainer with an
SSH session.

## Backends and execution

| Target backend | First binding to support |
| --- | --- |
| Local | File access rooted at an approved directory. |
| Memory | File access in a separate in-memory store for each Realm. |
| Docker | A disposable container with its workspace tree and Bash. |
| Apple Container | A disposable container with its workspace tree and Bash. |
| Sprites | Attach to or allocate a Sprite with a workspace tree and Bash. A retained binding can reopen the same place. |
| S3 | File access scoped to an approved bucket prefix. Writes use object preconditions where the file contract requires them. [S3 conditional requests](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-requests.html) |
| GitHub | File access scoped to an approved repository, branch, and path. The initial writable binding records file changes as commits on the approved branch. A binding pinned to a commit is read-only. [GitHub repository contents](https://docs.github.com/en/rest/repos/contents) |

The execution targets include **Lua**, **Bash**, **Python**, **JavaScript**,
and **Wasm**. Realm runs mediated Lua on a Memory or Local tree. It runs
Bash, Python, and JavaScript with read-only inputs in Docker. The next
bindings can attach a writable sandbox tree or provide a Wasm runtime
with an explicit WASI interface. Verify the compiler
and the guest under their own grants when a job builds a Wasm artifact.
Each execution binding runs the same author, run, diagnose, and revise
job. A binding chooses a compatible tree and toolchain. A backend can
supply several parts of that binding together.

Use `Realm.exec` to run a Realm entry point with a host-selected toolchain.
A custom Profile can require controls from that specific runner. For
example, a Local file tree can supply inputs to a fresh Node process in
Docker. The Profile requires the runner to enforce read-only inputs,
private scratch space, loopback-only networking, and a non-root user.
The integration case checks those controls from within the program and
confirms its effects on the host. A compiled program follows the same
model. Run the build within its grants, then verify the resulting
executable within its own grants.
[Node containment case](test/integration/04_sandbox_and_setup/04_01_confine_code_to_approved_files/README.md)

SSH is an execution transport for a host-approved machine. A provider
can use it to attach to a borrowed machine. The binding also supplies a
scoped file adapter, such as SFTP, or a defined staging and publication
process. Both surfaces must address the approved remote working tree.
The host selects the target, verifies its key on every connection, and
keeps credentials outside the Realm. The remote environment supplies
any isolation the Profile requires. Report an unknown run outcome
when the connection closes and the provider cannot confirm the result.
Confirm stop through the remote process supervisor or an equivalent
provider control. Service ingress uses its own grants and lifecycle.

S3 and GitHub start as file Realms. Their initial contracts cover scoped
paths and per-file operations. A Profile that requires POSIX features
such as native rename or empty directories needs a binding that provides
them. If a later execution Profile stages one of these trees, it must
describe how changes become visible and how it handles conflicts.

## Extension surfaces

| Surface | Responsibility |
| --- | --- |
| **Placement and leases** | Allocate, attach, or reuse a resource. Report its identity and ownership. Release it under the agreed policy and reconcile uncertain operations. |
| **File storage** | Supply a rooted file view. Report supported tree operations, revision checks, and size limits. |
| **Execution** | Run the selected toolchain through the binding's execution transport. Report run state, bounded diagnostics, and the outcome of stop. |
| **Named commands and runtime bridges** | Register trusted handlers with a stable name, argument schema, and scoped grants. Expose them directly to the agent or through an approved runtime bridge. |
| **Tree access from execution** | Connect the program to the Realm tree through the same tree, approved mounts, mediated file calls, or a staged copy with a stated publication point. Enforce each tree or mount grant in both the file interface and the runner. |
| **Isolation controls** | Enforce mounts, outbound network access, and resource limits. The host can supply scoped secrets through an approved channel. |
| **Artifact presentation** | Store and present approved output with the access and retention the host grants. The host can use one presenter across file, local execution, and remote execution bindings. |
| **Service ingress** | Give authorized clients access to a ready service. Enforce private access or an explicit grant for temporary public access. |
| **Retention and recovery** | Preserve files or an environment, resolve a saved placement, or restore a snapshot. State which runs and routes survive. |

An adapter can supply several of these responsibilities, and a binding
can combine adapters. Transfer uses the file contract. Setup and resume
use the execution contract. Realm owns identity, agent-facing operations
and results, grant checks, and the work lifecycle. Providers implement and
enforce the capabilities they claim. The host chooses providers,
credentials, grants, quotas, and retention. Jido routes work to the agent.

The host supplies and trusts named command implementations. Realm
checks the same command and file grants for direct calls and calls
through a runtime bridge. A command can be available on a file Realm
and use its scoped file API. An agent-authored script runs under its
program grants. An installed toolchain binary follows the execution
and toolchain policy.

## Prove it through agent jobs

Give a live Jido agent a job through its normal interface. The fixture
supplies approved bindings and an independent observer. Run the same job
and assertions for each Profile that promises the contract. A lifecycle
exercise drives allocation and release through Realm so the observer
can verify what the provider did.

1. **Organize a note.** Run the same job against Local and Memory. Verify
   the final file and the removal of the draft.
2. **Copy between Realms.** Give one agent two named Realms. Verify the
   exact bytes on both sides and confirm that a conflict preserves the
   existing destination.
3. **Build and revise a program.** Write setup and source, run the program,
   diagnose a failure, edit it, and verify the result under the sandbox
   policy.
4. **Show a saved HTML artifact.** Run the publish and review job on Local
   and Memory, then present HTML from the coding job with the same contract.
5. **Fix and test a repository.** Run the same change on a local container
   and a remote execution binding. Verify the diff, test results, and
   output against the same revision.
6. **Preview work in a second Realm.** Copy a page from Local to a local
   container, start the application, and fetch the exact page over HTTP.
   Run the same job on a borrowed Sprite. Exercise public grant,
   expiry, and revocation separately.
7. **Hand off durable work.** Close the first agent's session. Let a second
   agent reopen the Realm and verify the files, setup recipe, and stated
   lifecycle of any runs or routes.

Today the named file jobs run through the plugin on Local and Memory.
Agents use Realm to run Lua, Bash, Python, and JavaScript. The Apple
Container example still starts its service from the test harness.
[Examples](examples/realm/README.md) ·
[Conformance map](docs/conformance-map.md)
