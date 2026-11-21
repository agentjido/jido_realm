# Jido Realm compatibility and coverage

- Review date · 2026-11-20
- Package · `jido_realm` 0.1.0
- Status · Proposed delivery scope

## Outcome

A Jido agent can run the same job through `Jido.Realm` when the host
changes the provider. The job declares which file, execution, presentation,
and retention capabilities it needs. Each adapter offers every useful
capability it can enforce and prove. A host can combine providers. For
example, a job can read a source file from S3, work on it in a sandbox,
and publish the result through a host presenter.

The main acceptance job is a coding agent that opens an approved workspace,
reads and edits code, runs a failing test, fixes the code, verifies the
result, and publishes an interactive HTML report tied to the tested
revision. An execution binding can also serve the application for review.
The same job state, file results, run results, and access rules apply
where the required capabilities are available.

## Findings from the package review

1. **Keep the existing adapter boundaries.** Placement and lease ownership,
   file operations, runners, previews, and presenters already have distinct
   extension points. The host can choose a runner separately from the file
   provider. Keep that split and keep provider SDKs and credentials behind
   the host boundary. [Extension surfaces](../../VISION.md#extension-surfaces) ·
   [Session assembly](../../lib/jido_realm/session.ex#L295)
2. **File capability discovery is too broad for provider selection.**
   Local declares `:files` and supports writes. Sprite also declares
   `:files` and implements approved reads. A `:files` profile can open
   either. `:tree`, `:revisions`, and `:streams` also group operations
   with different read and write requirements. A coding profile needs to
   require each operation it uses before open succeeds.
   [File capability mapping](../../lib/jido_realm/files.ex#L25) ·
   [Sprite operations](../../lib/jido_realm/provider/sprite.ex#L59)
3. **The VFS gate limits breadth.** Realm asks for atomic tree capture and
   checked edits even for reads. At the pinned VFS revision, Memory
   supplies both callbacks. VFS Local, ETS, Git, S3, GitHub, and Sprite
   need other mechanisms. Realm already has a remote file contract for
   conditional mutations, with controlled S3 and GitHub tests. It needs
   real transports. [VFS provider](../../lib/jido_realm/provider/vfs.ex#L13) ·
   [VFS Memory capture](../../../jido_vfs/lib/jido_vfs/adapter/in_memory.ex#L621) ·
   [Remote file contract](../../lib/jido_realm/files/remote_files.ex)
4. **Execution and service claims need more detail.** Docker stages
   read-only inputs and uses private scratch. Lua mediates reads and
   publishes checked drafts per file. A writable sandbox tree needs its
   own contract. Realm has a fixed runtime list and keeps the latest
   background result for a session. Service stop exists. Run cancellation,
   reconnect, and multiple run histories need their own contracts. Preview
   liveness defaults to true when an adapter omits its check.
   [Runner request](../../lib/jido_realm/runner.ex#L44) ·
   [Run status](../../lib/jido_realm/session.ex#L143) ·
   [Preview liveness](../../lib/jido_realm/preview.ex#L17)
5. **Continuity and verified handoff are partial.** A second agent can
   reopen a retained Local tree. A controlled provider proves retry after
   an uncertain allocation. The session ID identifies the current session.
   The artifact store keeps the published bundle in memory. Bundle
   collection reads files one at a time, so the bundle alone gives no
   guarantee that all files came from one tested revision.
   [Session result](../../lib/jido_realm/session.ex#L603) ·
   [Lost open reply](../../test/integration/06_provider_lifecycle/06_02_recover_a_lost_open_reply/lost_open_test.exs) ·
   [Artifact collection](../../lib/jido_realm/artifacts.ex#L49)

## Common Realm contract

The user requirement is one `Jido.Realm` API with broad adapter support.
The following details are proposals for that API contract.

| Surface | Portable requirement |
| --- | --- |
| Lifecycle and discovery | Preserve managed `open` and `close`, named Realm bindings, existing result fields, and Signals. Add effective capabilities for the current binding and caller. Report configured capabilities, profile requirements, and grants as distinct inputs. Report allowed modes and limits, including size and time limits. Use additive changes for existing bindings. |
| Files | Require rooted read access for each file binding. Declare create-if-absent, edit-existing, delete, list, directory mutation, rename, search, revision checks, and stream read and write as separate claims. Bound text operations and keep binary transfer byte-exact. Treat revision tokens as opaque. State whether a token covers file bytes, an object version, a file commit, or an entire tree. |
| Transfer | `copy` creates a new destination. `copy_stream` publishes only after it receives all bytes. `move` verifies the destination before it requests a revision-checked source delete. If deletion fails or is uncertain, keep the source outcome explicit and report the destination state. A rename claim must state its atomicity and conflict scope. |
| Execution | Keep `exec`, `start_run`, and status semantics. Describe each toolchain, literal argument and working directory rules, output bounds, and run controls. Declare file visibility as mediated, read-only staged inputs, a checked publication step, or a shared writable tree. Add cancel, reconnect, history, or terminal access as optional operations when the binding can prove them. An uncertain run remains uncertain until a later provider check resolves it. |
| Managed services | `start_service` returns a handle for a process Realm manages. A service can run without a listening port. Declare ports at start when the adapter needs them for setup. `stop_service` stops the managed process and removes its endpoints. Report restart and keep-awake behavior separately. |
| Endpoint access | `expose_port` creates a route to an approved port in the bound environment or to a port on a managed service. Check readiness before reporting the endpoint as ready. Default to private HTTP. Declare protocol support, temporary sharing, expiry, and revocation separately. `close_port` revokes the route while the process continues to run. |
| Published output | `publish` returns a versioned reference for a file or bundle from any readable binding with a presenter. The host uses the media type and optional entry point to display or offer the output for download. Record the tested source identity and output revision for a verified handoff. Retention can extend past lease close when the presenter supports it. |
| Retention | Keep Realm identity, provider resource identity, session or lease, snapshot, artifact, and route lifetimes distinct. State what survives close, owner loss, or restart. When a provider can still write after a lost reply, keep the placement unavailable to a new writer until the host can confirm it is safe. |
| Errors and controls | Preserve stable error and result shapes. Define capability absence, policy denial, conflict, timeout, and unknown outcome. Profile admission must reject missing required controls. Backend and transport details stay in host diagnostics. Denied calls leave the target unchanged. |

Host-known features such as a Git commit, a provider snapshot, or a
browser terminal can extend a binding with a documented capability or
host-approved command. Preserve common semantics before promoting a
provider feature to the portable API.

### Service, endpoint, and output lifetimes

`expose(ctx, :work, port: 3000, protocol: :http, access: :private)` can
route to a listener started by a terminal, an image startup command, or
another owner. The host approves the port within the bound environment.
Use a service handle when the adapter needs it to select the target.
Each endpoint belongs to a Realm lease. Close revokes the routes for that
lease. On a borrowed environment, Realm stops its own managed services
and leaves processes owned by the host running.

The gateway enforces the access grant for each endpoint. A provider route
can serve the same purpose if it enforces the required scope, expiry, and
revocation. Qualify HTTP first. Declare support for WebSocket upgrades,
TCP forwarding, wake on request, and continuous operation separately.
Files, running processes, and endpoint grants can each have a different
lifetime through idle, wake, and close.

## Storage and source control matrix

**Current evidence** describes the Realm entry point. A controlled test
supports the Realm contract. A host example supports only the exercised
composition. A proposed claim needs its own tests on the selected storage
implementation before documentation can advertise support.

| Binding | Current Realm evidence | Proposed file operations and extent | Provider-specific acceptance |
| --- | --- | --- | --- |
| Local POSIX | Real, borrowed or owned. Text files, tree, search, byte revisions, and streams. | Keep the full file contract on a host-controlled tree. Report root and writer assumptions. | Exclusive create, no partial stream, symlink policy, contention, and close preserves or removes the correct tree. Separate evidence is required for external writers. |
| Realm Memory | Real, borrowed or owned. Text files, tree, search, byte revisions, and streams. | Keep full file coverage and report process-bounded retention. | Two isolated stores, atomic edits, and borrowed store survives Realm close. |
| VFS Memory | Real, borrowed. Note and copy in each direction cover basic text operations. | Add tree and search, opaque checked revisions, and streams where the adapter can enforce their guarantees. Use native atomic capture where applicable. | Direct VFS observer, two writers, failed mutation leaves the tree intact, and store survives close. Verify streaming separately from capture-based reads. |
| VFS Local | No direct binding at the pinned version. Realm Local is available. | Add a VFS binding with reads, list, search, and streams. Enable writable operations when their exclusivity and checked mutation pass. | Use one shared storage implementation per binding. Prove exclusive create, root confinement, external-writer assumptions, and interrupted-stream behavior. |
| VFS ETS | No direct binding at the pinned version. | Exercise read and file updates, tree, streams, and versioning under this store's process lifetime. Offer checked writes only where tested. | Competing writes and direct ETS-backed VFS observation. Prove what survives store process exit. |
| Git checkout and VFS Git | A host-cloned checkout works as a borrowed Local Realm. The VFS Git adapter can initialize or open a repo and commit. Direct VFS Git binding is missing. | Bind an approved clone or worktree to the file API. Offer approved ref, base commit, diff, and scoped commit. Treat push as explicit publication under separate authorization. | Clone an approved ref, verify the exact tested diff and commit, keep repository control data outside the writable file view, and preserve other branches and worktrees. |
| S3 | Controlled `RemoteFiles` case. The VFS S3 adapter can stage objects for a Local Realm. | Bind a bucket and prefix for read, list, and streams. Support create-if-absent and conditional update and delete where available. Report object revision and reconciliation. Define directory projections as prefix views. | Test against AWS S3 with scoped credentials and an adjacent prefix. Check conditions at the store, multipart cleanup, and lost replies. Verify each S3-compatible service separately. [AWS conditional deletes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-deletes.html) |
| GitHub Contents | Controlled `RemoteFiles` branch and commit case. Direct VFS GitHub binding is missing. | Read a selected branch or immutable commit. Support write and delete on an approved branch using the expected file SHA. Return the resulting commit. | Live test with a disposable repo or branch. Confirm the request carries the branch, the resulting commit is correct, and a later branch edit leaves pinned reads intact. [GitHub Contents API](https://docs.github.com/en/rest/repos/contents) · [Current VFS implementation](../../../jido_vfs/lib/jido_vfs/adapter/github.ex#L157) |
| Sprite filesystem | Realm owns or borrows a Sprite through the Elixir SDK. Approved file reads and lifecycle have controlled evidence. A live lifecycle test is opt-in. | Use the SDK and one rooted tree for file operations and the runner. Add list, writes, search, and streams behind separate claims. Check which VFS Sprite primitives can be reused. | Observe the exact same tree through SDK calls and commands. Verify bounded reads, path scope, atomic claims, and correct close for both ownership modes. [Fly.io Sprites](https://docs.fly.io/sprites) · [Elixir SDK](https://hex.pm/packages/sprites) |
| E2B and Daytona sandbox files | No Realm binding. | Give each provider a rooted file view for its execution tree. Reuse the common file and transfer jobs. Expose safe writes and independent stream capabilities where proven. | Verify exact bytes both through Realm and inside the sandbox. Race a file operation against a command that touches the same file. Check the reported result and revision scope. |

For VFS integration, use the smallest checked primitive that fits the
operation. For example, an S3 ETag precondition does not require capturing
an entire bucket. Keep the VFS adapters responsible for storage and
Realm responsible for grants, lease policy, and normalized results.

## Execution, presentation, and retention matrix

Combine a storage row and an execution row only when the host can prove
the file visibility and controls of that combination. A writable checkout
and a read-only staged runner are two separate capabilities.

| Binding | Current Realm evidence | Proposed extent | Provider-specific acceptance |
| --- | --- | --- | --- |
| Local, Realm Memory, or VFS alone | File bindings. Local reopen is tested. Memory lifetime follows its store. | Common file and artifact workflows. Pair with a separate runner if the job needs execution. | Verify a different agent can read a retained tree under different grants. State which store survives restart. |
| Mediated Lua | Real on Local and Realm Memory. Bounded progress, checked per-file publication, and failure behavior. Requires a revision-capable binding. | Extend to any binding that can prove mediated reads and checked publication. Declare partial publication when a later file is uncertain. | Run against a concurrent edit, fail a build after drafts exist, observe output limits, and verify the exact changes. |
| Docker | Real Bash, Python, and JavaScript runs. The Phoenix and TypeScript cases check staged source and service cleanup. The Phoenix case also checks native ripgrep. | Keep staged mode. Add a managed writable workspace for setup, test, logs, service control, and endpoint access. Reserve loopback mappings when creating the container. Qualify a private container network path for ports selected later. Verify further runtimes by image and version. | Assert same-tree visibility, preserve the file boundary, verify limits and cleanup, and confirm that service stop or lease close removes its endpoints. Test an unmapped port separately. [Docker port publishing](https://docs.docker.com/engine/network/port-publishing/) |
| Apple Container | Staged runner and service adapter for an owned Local placement on Apple silicon. Phoenix and TypeScript verify offline checks, read-only source, stale-source rejection, and loopback service cleanup. | Qualify more images, runtimes, and retention modes. | Verify each claimed control on the target host. The checked-preview case covers source isolation and port release. [Apple Container networking](https://github.com/apple/container/blob/main/docs/networking.md) |
| Sprites | SDK-backed file provider only. | Add execution, logs, and managed services. Forward ports through the Realm gateway with the Elixir SDK (`sprites` on Hex). Qualify service restart after idle and the Tasks hold for work that must keep running. Add retained reopen and checkpoints where supported. | Test owned and borrowed Sprites on a real account. Check the selected port, revoke access independently of the process, and repeat after idle and wake. Show that retained files survive a new lease. Check wake on the selected route before claiming it. [Sprites networking](https://docs.fly.io/sprites/working-with-sprites#networking-urls-and-port-forwarding) · [Service and task lifetimes](https://docs.fly.io/sprites/keeping-sprites-running) |
| E2B | No Realm adapter. | Qualify job execution, same-tree files, setup from a selected template, logs and stop, and private endpoints. Add pause and resume as separate retention claims. | Observe allocation identity, command result, close and reopen. Test state through pause and resume under the selected mode, and check whether old access is still accepted. [E2B persistence](https://docs.e2b.dev/sandbox/persistence) · [E2B network controls](https://docs.e2b.dev/network/internet-access) |
| Daytona | No Realm adapter. | Qualify job execution, scoped files, logs and stop, stop/start retention, snapshots, and port-specific signed endpoints with expiry and revocation. | Distinguish filesystem retention from process retention by sandbox class. Check signed-link revocation with a separate client. Keep sandbox-wide credentials at the host. [Daytona persistence](https://www.daytona.io/docs/en/persistence/) · [Daytona previews](https://www.daytona.io/docs/en/preview/) |
| Trusted native services | Real `erlexec` loopback HTTP previews. Host fixes the executable and arguments. | Keep `erlexec` as the native service mechanism. Cover service diagnostics, owned process-group cleanup, and gateway access across supported hosts. | Stop the full group. Confirm cleanup before lease release. Deny route access and keep the lease when cleanup is uncertain. |
| Wasm and WASI | `:wasm` is a recognized runtime name. No adapter. | Candidate for a scoped guest runtime with explicit filesystem and host capabilities. | Compile and run an artifact with only approved directories. Verify memory and time limits and guest cleanup before making claims. [Wasmtime WASI configuration](https://docs.wasmtime.dev/api/wasmtime_wasi/struct.WasiCtxBuilder.html) |
| Managed SSH host | A conformance case is defined. No production adapter. | Candidate for a trusted remote workspace, commands, stop and reconnect, and private tunnel ingress when needed. | Verify host and placement identity, stop with a separate observer, and exercise loss of transport without duplicate writes or allocation. |
| Artifact presenter | Real in-memory presenter with browser evidence. Available across readable bindings with host configuration. | Publish verified source references and retained artifact versions. Support a persistent presenter under the same agent API. | Capture one tested source revision, authorize every asset, show user interaction in a browser, and verify expiry, revocation, and persistence after the relevant restart. |

## Coverage and acceptance

The current macOS suite passed 154 tests with Docker and browser lanes
enabled. It excluded four tests across Apple Container, live Sprite, and
LM Studio. The S3 and GitHub tests in that total used controlled transports.

Use the existing integration ladder and `realm_case` fixtures in the
main `jido_realm` Mix project. Each fixture provides a binding, approved
inputs, an independent observer, and cleanup. Lifecycle tests use Realm
to request and release the placement. Check the real effect before
fixture cleanup can hide it.
[Integration ladder](../../test/integration/README.md) ·
[Shared case harness](../../test/support/conformance/scenarios.ex)

| Coverage requirement | Ladder cases and case designs | What must count as evidence |
| --- | --- | --- |
| Baseline on every claimed file binding | 00.01–00.04, 02.01–02.03. Use chapter 01 for claimed file operations. | Select read-only or writable assertions from the claim. Verify access restrictions and exact bytes. Run rejected operations and confirm they reach neither storage nor compute when Realm denies them at admission. |
| Transfer between unlike bindings | 01.03–01.05, 08.01 | Cover Local ↔ Memory, a checked object store ↔ Local, and Local ↔ a hosted workspace. Exercise conflict, interrupted stream, and uncertain delete on the providers that claim the corresponding operation. |
| Code and isolation | 03.01–03.07, 04.01–04.07 | Execute on the actual toolchain. Test the advertised working-tree mode, network policy, resource controls, and stop behavior. Use controlled failures for lost replies and independently observe the runtime in live tests. |
| Services and endpoints | 05.01–05.03, 08.01 | Run two Realms on the same guest port and check that each route reaches the correct listener. Expose a host-owned listener. Revoke one route and verify that the process and the other route still work. Check readiness failures, access denial, expiry, service stop, and lease close. Repeat after idle and wake where claimed. |
| Published output | 08.02–08.03 | Run a browser against the saved bundle. Verify the tested source revision and output bytes after close where retention is claimed. |
| Ownership and recovery | 06.01–06.05, 07.01–07.05 | Observe identity and ownership, independent cleanup, retained reopen, expected snapshot content, and rejection of a stale writer. Treat a lost response and loss of the controller as separate cases. |
| LLM behavior | 09 model-driven files | Keep the opt-in LM Studio/Qwen pressure test. Repeat the coding-and-review job with a model after deterministic tests establish the portable behavior. Treat model trials as evidence of agent behavior with that model and tool configuration. |

Track one result for each **binding × capability × case × environment**
combination. Record provider and toolchain versions, evidence type, and
outcome. Distinguish a passing real backend from a passing controlled
transport, an example, an excluded or unrun case, and an unsupported
capability. If a configured binding promises a capability and its case
fails or cannot run, that lane cannot pass. Keep the same case ID for
the same behavior. Add a specific provider case only for a different
guarantee or failure mode. Coverage measures claims with matching
evidence. More tests or more providers alone do not increase that coverage.

Default checks exercise local stores and controlled transports. Opt-in
lanes exercise Docker, browser, Apple Container, and dedicated provider
accounts. Require live evidence before promoting a remote adapter's
claims. Test package compatibility separately on the supported
Jido, Elixir/OTP, and host OS combinations. The manifest declares Elixir
`~> 1.18`; the local review used Elixir 1.20.4 and OTP 29. Check the
minimum supported versions with the required `erlexec` build and the
Sprites and Cowlib constraints. Verify the public API from a separate
Jido consumer with its own dependency resolution. [Dependency manifest](../../mix.exs)

### Doctor and compatibility helpers

- **Current preflight.** `mix jido_realm.doctor` reports local readiness
  for the core, native, Docker, browser, Apple Container, Sprite, and LM
  Studio lanes in text or JSON. Use `--lane` and `--strict` before a
  required CI lane. The report gives a reason and an action for each
  missing prerequisite. The Sprite checks report credential presence only.
  The LM Studio check reports local TCP reachability. The doctor does not
  allocate resources or certify provider behavior. Run the integration
  ladder to establish that evidence. [Realm doctor](../../README.md#check-host-and-test-prerequisites)
- **Profile preflight.** Extend the doctor from known lanes to the host's
  configured profiles when effective capability details are available.
  Litter Box's `doctor` combines host probes with a report for each profile.
  [Doctor](https://github.com/zblanco/litter_box/blob/main/lib/mix/tasks/litter_box.doctor.ex) ·
  [Profile health report](https://github.com/zblanco/litter_box/blob/main/lib/litter_box/reports.ex#L191)
- **Normalized capability details.** Litter Box reports transport,
  workspace and state details with backend capabilities. Use the same Realm
  capability description for profile admission and the preflight report.
  Include the file visibility mode, the available attach and endpoint
  modes, and what survives idle or close. A ready provider can still lack
  a required capability. Reject that profile before it runs the job.
  [Litter Box architecture](https://github.com/zblanco/litter_box/blob/main/ARCHITECTURE.md#capabilities)
- **Separate service and proxy handles.** Litter Box has separate start,
  stop, open proxy, and close proxy calls. Realm can use that split and
  allow a route to an approved port on a borrowed environment. Keep
  provider handles behind the Realm adapter.
  [Litter Box service and proxy API](https://github.com/zblanco/litter_box/blob/main/lib/litter_box.ex#L373)

## Delivery boundaries and decisions

| Work area | Boundary and completion condition |
| --- | --- |
| Common API and evidence | A profile can request read-only or writable behavior and the exact execution and access controls it needs. Existing callers keep their result fields. Tests and the matrix agree on the effective claims. |
| File providers | Local, Memory, checked VFS bindings, a Git checkout, live S3, and a live GitHub branch cover the file roles listed above. Verify the required storage semantics before enabling mutations. VFS changes belong in `jido_vfs`. A VFS release or a reviewed Git pin must precede any Realm dependency that requires new VFS behavior. |
| Compute and presentation | Run the same deterministic coding-and-review job against the approved Docker, Apple Container, Sprite, E2B, and Daytona profiles. Retain the native `erlexec` lane for trusted services. Direct Fly Machines support is out of scope for this delivery. |
| Compatibility helpers | Use the doctor for lane preflight and `realm_case` for conformance. Build profile-level reporting on the same capability details that Realm uses for admission. |
| Durability | A second agent reopens exactly the approved source and output. Snapshots and process or route recovery have separate tests where the adapter claims them. Verified handoff references survive the changes and restarts promised by the binding. |

Realm maintains its own adapter tests and docs. Provider account
provisioning, paid test runs, production credentials, and implementations
belong to later authorized work. Wasm and SSH are candidate bindings in
this scope. Admission to the first delivery requires an explicit choice.

The work owner still needs to choose the first hosted reference binding,
the host OS and Elixir/OTP release floor, and the live test account and
cost limits. The owner also needs to decide whether the first durable
release covers only source, outputs, and setup, or includes recovery of
running services. These decisions apply to delivery. The scope and
shared coverage contract inform the [production delivery plan](realm-production-delivery.md).
