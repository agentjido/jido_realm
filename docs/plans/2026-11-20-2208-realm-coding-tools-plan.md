---
title: Give Jido agents standard coding tools in a Realm
type: implementation-plan
date: 2026-11-20
last_reviewed: 2026-11-20
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Give Jido agents standard coding tools in a Realm

## Goal Capsule

Give a host-side Jido agent a standard set of tools to find, read, edit, run,
test, and show code in its named Realm. Use the existing Realm contracts and
prove the flow on Docker and local Apple Container. This request authorizes
the local plan. A Realm maintainer can implement it with separate local-write
authority. Stop a verification lane if its required capability or baseline
check fails. Retain the working tree when a repair turn runs out of time or
tool calls.

## Product Contract

### Summary

Use familiar tools such as ripgrep and Bash. Keep tool names and results
consistent when the host changes the Realm binding. Give the agent enough
information to fix a failed check without losing earlier work.

### Problem Frame

The Apple Container run proved one agent can carry three edits through one
Realm. Its test harness supplied the file tools, run control, and preview.
Discovery calls and stale revisions used up repair time. The first 404 attempts
also showed why the host must validate the app fixture and the check separately.

### Actors

The host gives the agent a Realm, grants, and approved checks. The agent uses
the coding tools. The provider holds the files and runs commands if it has that
capability. The host and browser observe the result.

### Requirements

- **R1.** Find files, search content, read, create, and edit through standard
  coding actions. A successful checked write gives the agent the new revision.
  A conflict leaves the file intact and tells the agent how to continue.
- **R2.** Run Bash and approved checks in the selected execution environment.
  Tie each check to the inputs it used. Give the agent enough evidence to
  continue from the same Realm after a failed test or an interrupted turn.
- **R3.** Run the same coding flow through production Realm contracts on Docker
  and Apple Container. Start and stop a private service on the tested source.
  Confirm readiness and cleanup independently.
- **R4.** Keep the file tools usable on Local and Memory. Add execution tools
  only when the selected binding satisfies their requirements. Preserve the
  established Realm API and operation grants.

### Key Flows

Inspect available tools and checks → find and read files → create or edit →
run a check against a known source version → repair or accept → start a
private service on the accepted source → observe and close.

### Acceptance Examples

| Case | Expected result |
| --- | --- |
| Find and edit | `glob` locates tests, `grep` finds a function, and `read` returns its text and revision. `write` creates a test and returns its revision. `edit` can use that revision immediately. |
| Competing edits | Two callers read the same revision. One edit succeeds. The other receives a conflict, reads the current bytes, and chooses how to repair them. |
| Failed check | A test fails against source A. The agent fixes the code and the same check passes against source B. The result identifies both the command and the exact checked inputs. |
| Interrupted turn | The host can resume work in the same Realm with the changed paths and last confirmed check. An uncertain run is reconciled before a retry can duplicate its effects. |
| Serve and inspect | The same three-turn Phoenix job adds an introduction, a JSON endpoint, and a custom 404. A browser follows the 404 link home. The run records service and route cleanup. |

### Success Criteria

The standard tools work through normal Jido action dispatch. The repeatable
tests prove current revisions, red and green checks, and recovery. On a local
Apple silicon Mac, the LM Studio case records three accepted diffs from one
Realm session and four independently observed browser states.

### Scope Boundaries

This delivery covers Local and Memory files, Docker execution, and Apple
Container execution and private service access. Existing compatibility work
owns Sprites, E2B, Daytona, remote retention and publication. The core actions
use capability checks so later providers can join without changing agent
prompts. Release and provider-specific work outside this set have separate
plans.

### Key Decisions

Use the existing named Realm and host grants. Keep the agent on the host in
the verification fixture. Use one set of actions and one coding job across the
qualified bindings. Treat the browser as an observer of the served revision.

### Rejected Alternatives

A complete agent framework in Realm would duplicate Jido turn control.
Separate tool schemas for each provider would require the agent to change its
workflow when the host changes the binding.

### Dependencies

The package's existing Jido and VFS dependencies, Docker, an eligible Apple
silicon Mac, the pinned Phoenix fixture, and LM Studio with a model that can
make structured tool calls. The host supplies a reproducible coding image
with Bash, ripgrep, Elixir, and Mix.

### Outstanding Questions

None identified for this scope.

### Sources

- [Apple edit case and local run instructions](../../test/integration/09_model_driven_files/README.md)
- [Integration ladder](../../test/integration/README.md)
- [Compatibility scope](realm-compatibility-scope.md)
- [Claude Agent SDK tool permissions](https://code.claude.com/docs/en/agent-sdk/permissions) shows the conventional `Read`, `Glob`, `Grep`, `Write`, `Edit`, and `Bash` actions.

## Planning Contract

### Product Contract Preservation

The direct request selects familiar coding tools. The preceding run supplies
the recovery, test, and preview cases. This plan applies them to the existing
Realm API and selects the first provider bindings that will prove the contract.

### Current System

`Jido.Realm.Plugin` resolves a named binding. `Jido.Realm.file/5` applies file
grants and dispatches to the backend. `read_revision` returns an opaque token.
Successful local mutations return the operation and path. `search` already
supports bounded literal matches. `exec/5` accepts an entry point plus literal
arguments and returns a bounded run result. `invoke/4` runs a host-registered
command. Session tracks operations and cleanup. Docker has a runner and preview
adapter. The live Apple case opens a Local placement and uses its test helper
to run Apple Container commands and serve the files. Jido Shell has a mediated
Bash backend with its own VFS bridge. [Files](../../lib/jido_realm/files.ex) ·
[Realm API](../../lib/jido_realm.ex) · [Session](../../lib/jido_realm/session.ex) ·
[Apple guest helper](../../test/integration/09_model_driven_files/apple_edit_guest.exs) ·
[Jido Shell Bash backend](../../../jido_shell/lib/jido_shell/backend/bash.ex)

### Target System

Publish a small set of typed Jido actions that use a named Realm. The host
registers actions for the profile it selected. Action dispatch checks the
effective capability, grant, and approved path or command before execution.
The host supplies the working directory, prepared toolchain, and private
service configuration.

| Action | Contract |
| --- | --- |
| `glob` | Find relative paths with a bounded glob under an approved directory. |
| `grep` | Return relative paths, line numbers, and bounded match text. Use ripgrep when the binding can search its authorized file view. A files-only binding can supply literal matches through its existing search. Advertise regex support explicitly. |
| `read` | Read one file or a small batch of files with optional line ranges. Include each file's revision when supported and mark truncated or partial results. |
| `write` | Create a file exclusively and return the revision of the committed content. |
| `edit` | Replace one exact text match. Require the observed revision and return the new one. Report absent or ambiguous text separately from a conflict. |
| `bash` | Accept a command, a Realm-relative working directory, and an optional timeout within the host's limit. Return the run ID, exit code, and bounded output. Use the guest's tools for build commands and for `git status` or `git diff` when the host provides Git and an approved checkout. |
| `run_check` | Accept a host-approved check name and an optional expected source reference. Return the check ID, run ID, confirmed source reference, result, and bounded diagnostics. |

The host assigns a request ID before dispatching Bash or a check. It retains
the ID across lost replies so it can query the same operation.

### Key Technical Decisions

- **KTD1. Use thin actions over Realm operations.** Normal file work uses
  Realm's existing backends and path policy. Add bounded directory discovery
  and batch reads over that API. Use ripgrep with fixed arguments against an
  approved mounted or staged view. Apply the same read scope to native and
  mediated search. Ordinary discovery fits one or two calls. A second shell
  abstraction would duplicate the existing runner and grant checks. This
  governs R1 and R4 in U1.
- **KTD2. Return confirmed revisions and preserve the tested inputs.** Return
  the post-write token from the same checked mutation when the backend can
  confirm it. Preserve existing generic file results and provider commit
  metadata. Bind a check to a host-declared input set and prepared toolchain.
  Stage one coherent file view. Use a provider's atomic capture or hold a
  writer guard during capture. For a shared-tree check, hold the guard until
  confirmed stop. Admit this mode only when the host controls every writer
  that can change the admitted input set. A revision captured after execution
  could misstate what the process read. This governs R1 and R2 in U1 and U2.
- **KTD3. Run commands through the approved runner.** Add an explicitly
  supported Bash command form for a guest. Use a distinct runner request form
  and admit only adapters that advertise it. Keep the existing file entry
  point request form and literal arguments. Register verified checks as
  host-owned runner requests with a declared input set, toolchain, and result
  classification. Keep existing host callback commands available through
  `invoke/4`. Give the new coding profile a host-owned 30-second command and
  check limit. Use separate 150-second host setup and 30-second service
  readiness limits from the proven Apple fixture. Keep the existing
  `exec/5` defaults and validation for its current request form. Give the
  coding profiles read-only source and writable scratch. Existing declared output
  publication uses separate write grants. The actions support normal agent
  edits through `write` and `edit`. A Jido Shell bridge can qualify later by
  proving the same grants and controls. This governs R2 through R4 in U2 and U3.
- **KTD4. Separate the service from access to its port.** Implement guest
  start, readiness, stop, and route revocation in the existing adapter and
  Session seam. Keep `start_preview/5` and `stop_preview/3` as the public
  compatibility path for this delivery. An optional source reference on start
  selects a successful check. Re-capture the authorized tree under the same
  guard, compare its source and toolchain identities with that check, and
  start the service from the immutable stage. An intervening edit rejects
  start before allocation and requires a new check. The adapter can declare
  its port mapping before launch. The private gateway can provide an origin
  rooted at `/` for one service and authorize each request with
  `Preview.target/3`. This preserves links such as `href="/"`. Keep the
  existing path-based URL mode for existing hosts. Keep native trusted
  service execution on erlexec. This governs R3 in U3 and U4.
- **KTD5. Give a run a stable identity before it starts.** The host coding
  workflow supplies a request ID and keeps it through a lost reply. Session
  registers it before launch. The same ID and inputs return the recorded
  state. The same ID with different inputs is a conflict. Extend granted
  `run_status/3` lookup to these records. A host-authorized reconcile operation
  asks the adapter about the owned resource for that ID and confirms stop or a
  terminal result. If the process is gone and its result is unavailable,
  return a stopped outcome with no verified check result. Keep unknown runs
  fenced until confirmation. A new ID is required for a deliberate retry.
  This governs R2 in U2 and U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| Jido actions and file bindings | Generic file Signals plus example-local coding tools | Add opt-in coding actions. Use opaque revision tokens and structured conflict details. Reuse file grants and rooted paths. | Existing Signals keep their inputs and result meanings. Advertise only confirmed capabilities. |
| Session, runner, and commands | Separate workers for files and runs. Named commands can return host-defined results. | Use existing admission for bounded guest Bash and named checks. A known check result includes an input identity and terminal outcome. | Admit only a stable snapshot or enforceable writer guard for a verified check. Release the guard after confirmed stop. |
| Check record and recovery | Run status covers the latest background run. The example saves manifests and diffs. | Retain identity and terminal state until close for a host-bounded set of requests. Bound diagnostics and keep unresolved IDs until reconciliation. The host resumes with changed paths and the last confirmed check. | Keep file revision, verified source reference, and retained snapshot distinct. This recovery contract applies while the session is alive. Restart recovery depends on the provider's retention capability. |
| Guest service and port access | Docker and erlexec adapters. Apple Container helper in integration tests. | Move the Apple execution and private service lifecycle into package adapters. Use the same private route contract for both guest providers. | Confirm stop and route closure. Preserve an uncertain lease for reconciliation while a process can still act. |

### Implementation Units

#### U1. Find, read, create, and edit through standard actions

**Requirements** R1 and R4. **Dependencies** None.

Use `Plugin`, `FileAction`, `Files`, and the Local and Memory backends to
expose `glob`, `grep`, `read`, `write`, and `edit`. Bound traversal, bytes, line
ranges, and match counts. Keep authorization on each batch item. A failed item
has its own result. Search cannot read paths that the equivalent file action
would deny. Define equivalent literal results for native and mediated search.
Return the revision atomically on confirmed Local and Memory mutations. Report
`:conflict` with the affected path and require a fresh read. Exercise a real
agent action on both bindings. Verify the create-to-edit sequence, stale and
ambiguous edits, bounded batch and search results, and denied paths with an
independent file observer. Use mediated literal search for this gate. U4
qualifies native ripgrep with the production runners. Complete when both
file bindings pass these cases.

#### U2. Run Bash, check exact inputs, and resume after failure

**Requirements** R2 and R4. **Dependencies** None. This unit can use the
current revision operations and a deterministic agent before U1 is complete.

Use `Runner`, `Commands`, `Session`, and `RunAction` for guest Bash and named
checks. Select the Docker staged runner for the first real case. Add one
coding image recipe to the fixture. Pin the base by digest and pin Bash,
ripgrep, and the Elixir and Mix toolchain through the base or build inputs.
Use the same recipe for both engines. Record the resolved image ID per
engine. Check `bash --version`, `rg --version`, and `mix --version` in the
selected image before the job starts. Prepare dependencies from the existing
fixture lockfile. Validate input
identity before launch and record the toolchain and prepared inputs. A stale
expected reference fails before launch. Keep `test_failed`, `setup_failed`,
`timed_out`, and an unconfirmed provider outcome distinguishable. Respect host
deadlines and output limits. Prevent another writer from changing guaranteed
inputs. Register request IDs and implement lookup and reconciliation under
KTD5. Use the existing Docker resource name derived from the run ID to confirm
stop or absence. Use a bounded recovery turn from the same Realm with the
actual results and changed paths. Test a failing check, a fix on a new source
revision, a concurrent write during capture, timeout, and a lost reply. Count
guest launches to prove that duplicate submissions start one process.
Complete when a deterministic agent shows the exact source that failed and
passed and can continue from the last recorded state.

#### U3. Run and serve the same Realm on Apple Container

**Requirements** R2, R3, and R4. **Dependencies** U2 supplies the command,
input identity, and checked execution contract.

Move the applicable CLI lifecycle from the Apple guest helper into a
production runner and preview adapter. Mount the controlled Local tree
read-only for Bash and checks. Stage the verified inputs for the service and
keep that view fixed while the service runs. Use separate writable scratch
and host-approved dependency setup. Disable check networking after setup. Probe
the actual image, tools, mounts, and private port before advertising the
capability. Use stable guest names for reconciliation. Independently observe
readiness, denied writes, timeout, failed start, route closure, and owned guest
cleanup. Change the tree between the check and service start and verify
rejection. Edit again after service start and verify the service still shows
its staged version. Complete when a deterministic test and service run through
the production Realm API on Apple Container.

#### U4. Exercise the full coding job and publish run instructions

**Requirements** R1 through R4. **Dependencies** U1 for the standard tools and
U3 for the production Apple path. U3 already requires U2.

Use one scripted agent job on Docker and Apple Container. Qualify native
ripgrep in the prepared guest image with the same read scope as `read`.
Verify regex and literal modes, bounds, and denied paths. Drive the same
actions in the opt-in LM Studio lane on Apple Container. Supply a tested
baseline, project context, and named checks before the model edits. Keep the
acceptance fixture read-only and check the returned HTTP status and body.
Give the browser a private loopback origin for each service. The fixture
gateway authenticates the test viewer and checks `Preview.target/3` on every
request. Forward paths and queries to the service. Open `/api/realm` and the
missing page through the gateway. Click the home link and verify that the
browser stays on the same origin. Verify access revocation and port closure.
Preserve the accepted diffs, cumulative checks, tool traces, and browser
results. Update the coding-agent instructions and the Apple compatibility row
with observed results. Complete when the deterministic and live gates below
pass on their named bindings.

### Work Graph

U1 and U2 can start in parallel. U2 → U3 supplies the checked-run contract.
U1 and U3 → U4 combines the reusable actions and provider execution. The
critical path is U2 → U3 → U4. U4 is the final integration gate.

### Verification Contract

| Gate | Requirements and units | Evidence and completion signal |
| --- | --- | --- |
| File actions | R1, R4 · U1 | Local and Memory agent tests prove correct bytes, revisions, bounded reads and search, and conflict or denial without mutation. |
| Checked execution and recovery | R2, R4 · U2 | Docker records exact inputs and red and green outcomes. Test stale inputs, concurrent capture, bounded output, timeout, a lost reply, and a repeated request. Confirm one guest launch. Reject unsupported capabilities before launch. |
| Apple lifecycle | R2, R3, R4 · U3 | Confirm read-only source and an offline test guest. Reject source changes before verified start and isolate the running service from later edits. Observe readiness and port closure. |
| Shared job | R1–R4 · U4 | Deterministic Docker and Apple jobs use the same actions and verify real ripgrep results. Apple LM Studio completes three turns. Capture tool traces, diffs, source references, and browser and cleanup evidence through the private gateway. |
| Package regression | R1–R4 · U1–U4 | Default suite passes. Existing Signals, Docker staged inputs, native erlexec service behavior, and file-only bindings retain their documented behavior. |

Run from `jido_realm` with the package dependencies prepared. Run the focused
new action and adapter tests before the broad gates. Start Docker and Apple
Container. Build or load the new fixture image in both engines and export
its reference as `JIDO_REALM_CODING_IMAGE`. The new coding profiles read that
reference. The doctor commands below direct the existing lanes to the same
image. The regular Docker integration prerequisites still apply. Load the
selected LM Studio model before the live lane.

```sh
mix test
JIDO_REALM_BASH_IMAGE="$JIDO_REALM_CODING_IMAGE" mix jido_realm.doctor --lane docker --strict
mix test --include docker --include browser
JIDO_REALM_APPLE_IMAGE="$JIDO_REALM_CODING_IMAGE" mix jido_realm.doctor --lane apple_container --strict
mix test test/integration/09_model_driven_files/apple_edit_agent_test.exs --only apple_container
mix jido_realm.doctor --lane lmstudio --strict
JIDO_REALM_APPLE_EDIT_BROWSER=1 mix test test/integration/09_model_driven_files/apple_edit_agent_test.exs --only lmstudio --max-cases 1
```

### Rollout and Recovery

Introduce the actions and Apple adapter as opt-in capabilities. The host can
disable them by selecting the earlier profile. Reconcile an active or uncertain
run before changing its binding. Preserve the working tree and evidence when
the agent stops. Only the host accepts a tested revision or starts the next
repair turn. Confirm guest and route cleanup before releasing an owned lease.

### Risks and Assumptions

- A test can read hidden inputs such as generated files or dependencies. Include
  these in the declared check inputs or prepared toolchain identity. Distinguish
  a checked file set from a full repository snapshot.
- A guest with write access could change files outside the checked-edit path.
  The first coding profiles use read-only source mounts. Qualify writable guest
  modes separately when the provider can enforce their file policy.
- Ripgrep behavior depends on the selected file view and executable. Verify the
  tested image and publish the supported search modes. The Memory case needs
  only its mediated literal search.
- An LLM run can fail independently of the Realm implementation. Use the
  deterministic job to check Realm behavior before running the model lane.

### Open Planning Decisions

None block U1 or U2. Providers with retained writable guests and public port
access follow the compatibility plan. The Realm maintainer owns those separate
capability decisions.

### Definition of Done

The standard tools pass their Local and Memory tests. The Docker and Apple
Container jobs verify the source that was tested and served. The Apple live
case passes three edits in one Realm and records the 404 check before and after
the edit. The browser confirms the cumulative behavior. Cleanup is independently
confirmed. The default suite passes, and the package documents the supported
actions and provider capabilities.

### Planning Sources

- [File action and revision inputs](../../lib/jido_realm/file_action.ex)
- [Runner and control admission](../../lib/jido_realm/runner.ex)
- [Host-approved commands](../../lib/jido_realm/commands.ex)
- [Docker runner and preview](../../lib/jido_realm/runner/docker.ex)
- [Preview adapter contract](../../lib/jido_realm/preview.ex)
- [Existing private gateway integration](../../test/integration/05_services_and_routes/private_preview_test.exs)
- [Toolchain case](../../test/integration/03_program_execution/03_02_build_and_test_with_a_toolchain/README.md)
- [Production delivery plan](realm-production-delivery.md)

## Adapter Results

- Markdown: canonical in this file.
- HTML: not requested.
- Beadwork: not requested.
