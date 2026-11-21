---
title: One file contract for Jido Realm
type: implementation-plan
date: 2026-11-20
last_reviewed: 2026-11-20
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# One file contract for Jido Realm

## Goal Capsule

- **Objective.** Prove that a live Jido agent can manage files through the same Realm Signals on different backends.
- **Means.** Register ordinary ExUnit exercises once and run them against isolated backend profiles.
- **Authority.** This request authorizes the plan. Implementation and live provider access need their own authorization.
- **Stop conditions.** Local and Memory pass the same suite, and both fixtures confirm the effects in their backing stores.
- **Next executor.** The Realm implementer starts with the Local contract.

## Product Contract

### Summary

Jido Realm gives an agent a place to work. Agents use one file interface across implementations. The initial exercise creates, reads, edits, and deletes a file in a live agent session.

### Problem Frame

The current Local test proves the first exercise. It also assumes a disk path and expects POSIX error names. A shared suite needs to express what the agent can rely on and prove that the selected backend performed the work.

### Actors

- A Jido agent sends Realm file Signals.
- Host code selects and configures the backend.
- A test author adds exercises. A backend implementer supplies a test fixture.

### Requirements

| ID | Requirement |
| --- | --- |
| R1 | One agent-facing contract defines Signal names, inputs, replies, errors, and file semantics. |
| R2 | Declare an exercise once. Run its assertions against each selected profile through a live agent. |
| R3 | Verify that the selected backing store contains the expected bytes after writes and reports absence after a delete. |
| R4 | Run Local and Memory without provider credentials or network access. Future profiles must be able to join the same suite. |

### Key Flows

The fixture creates a fresh backing store or namespace. The harness starts the same agent and supplies its host options. Each exercise calls `Jido.AgentServer.call/3` with the same Signals and checks the raw turn result. The fixture can observe the store directly. The harness stops the agent before fixture cleanup.

### Acceptance Examples

- Create an empty `notes.txt`, read it, edit it to a nonempty UTF-8 string, read the new bytes, delete the file, and confirm it is missing. Check creation, replacement, and deletion in the backing store as well.
- A second create returns `:already_exists` and preserves the original bytes. Edit, read, and delete on a missing file return `:not_found`.
- An absolute path or a parent component returns `:invalid_path`. The Local regression test also checks symlinks and verifies that the outside file stays intact.

### Success Criteria

Switching from Local to Memory changes fixture configuration only. Both backends run every required exercise with the same assertions and observable results. A backend that returns success without storing bytes fails the suite.

### Scope Boundaries

The first delivery covers UTF-8 files, existing roots, and Local and Memory. Sprite, Dropbox, and Apple Container are extension candidates. Command execution, snapshots, binary data, concurrent writers, and provider provisioning each need their own exercises. An Apple Container profile can take the file contract when it exposes a Realm tree. Command isolation belongs in an execution contract.

### Key Decisions

The host selects the backend. A required assertion applies to every profile that claims the file contract. A test can use provider-specific setup and observation through the fixture.

### Rejected Alternatives

A standalone Mix task would need to duplicate test registration, assertion reporting, filters, and cleanup. Use ExUnit as the runner. Add a Mix task later if there is a concrete need to provision live fixtures or report results from several environments.

### Dependencies

The current project uses Elixir 1.18 or later and Jido from `release/v3`. ExUnit parameterization is available at the project minimum. The first delivery uses the existing dependencies.

### Outstanding Questions

The project owner can select the first live profile after Local and Memory pass. That choice also requires an approved test location and resource lifetime.

### Sources

[Current file Signals and usage](../../README.md) · [Local agent tests](../../test/jido/realm_test.exs) · [Mix project](../../mix.exs)

## Planning Contract

### Product Contract Preservation

The direct request establishes one interface for agents and a suite that can run the same exercises across implementations. The plan uses Local and Memory to prove those properties before it adds a live provider.

### Current System

The plugin derives four routes and passes the host's root into live admission. `FileAction` calls `Local.run/4`, builds a `realm.file.result` reply, and wraps native error atoms in Jido error details. `Local` resolves relative paths, rejects symlinks, and stages creates and edits. The existing tests use a real agent, and the file lifecycle test checks the disk directly. [Plugin](../../lib/jido_realm/plugin.ex) · [Action](../../lib/jido_realm/file_action.ex) · [Local implementation](../../lib/jido_realm/files/local.ex)

### Target System

```text
Agent Signal → Realm plugin and file action → host-selected backend
            ← one reply or error contract ← backend result

ExUnit exercise → live AgentServer
                → fixture observer → selected backing store
```

### Key Technical Decisions

- **KTD1. Use one thin ExUnit macro for the file contract.** It declares ordinary `test` cases and passes a literal profile matrix to ExUnit's built-in `parameterize:` option. This gives each exercise and profile its own result and cleanup. ExUnit owns execution and filtering. Governs R2 and R4, U1 and U2.
- **KTD2. Normalize at the Realm boundary.** Keep the existing Signal names, success data, and Jido turn statuses. Return stable failure reasons such as `:already_exists`, `:not_found`, and `:invalid_path` in `error.details.reason` on a failed turn. The shared assertions inspect those values directly. Map native failures where they enter the Realm contract. The spike's callers that match `:eexist`, `:enoent`, or `:symlink` must move to the normalized values. Preserve Local path and symlink enforcement. Governs R1, U1 and U2.
- **KTD3. Prove that the selected store changed.** A fixture supplies host options and an observer that reads file contents or absence directly from that store. This catches a backend that reports success from an echo or fallback. Provider client calls belong in the fixture. Shared test bodies always use Realm Signals to perform work. Governs R2 and R3, U1 and U2.

Proposed declaration in a test module:

```elixir
use Jido.Realm.Conformance.Files,
  profiles: [local: LocalFixture, memory: MemoryFixture]
```

Add each new exercise as an ordinary ExUnit test in the shared contract module. Keep the harness under `test/support/` until a project outside Realm needs to import it.

### System Boundaries and Change Surface

| Surface | Planned change | Compatibility or risk |
| --- | --- | --- |
| Agent API in `Plugin` and `FileAction` | Keep `realm.file.create/read/edit/delete` and `realm.file.result`. Centralize relative path and required write content checks. Preserve operation and path in success data, and return content on read. | Update the existing error expectations and document the stable reasons. Distinguish timeouts and backend faults from a missing file. |
| Host and backend | Preserve `root:` as the Local setup. Add `backend: {module, handle}` in the host runtime options. Validate explicit bindings and reject conflicting options. Define a small internal file interface for the four operations. | Backend state and credentials stay with the host. Signal data has no backend selector. Backend-specific checks, including Local symlinks, still run. |
| Test fixture | Supply runtime options for a fresh store, an `observe(path)` function that returns bytes or reports absence, and cleanup. Local uses a temp directory and direct file reads. Memory uses a fixture-owned store and direct state reads. | Isolate each exercise's store and agent. Mark a provider profile as passed only if the test selected it and its observer confirmed the effects. |

### Implementation Units

#### U1. Bind the shared file contract to Local

- **Requirements and dependencies.** R1–R4. Starts here.
- **Affected surfaces.** `Plugin`, `FileAction`, `Local`, the existing agent tests, test support, and the README.
- **Direction.** Put runtime backend selection behind the existing routes. Keep the Local root option. Add normalized error handling and the thin contract macro. Extract the common lifecycle, duplicate/missing cases, and path cases. Keep a Local-only test for symlinks. Configure the Local fixture to observe the actual directory.
- **Proof.** Run the tagged shared tests with Local and run the full suite. Check empty and changed byte content, duplicate create, missing files, traversal, and symlinks. Confirm the documented Local setup still starts a live agent.
- **Completion.** Local passes every required exercise through the new shared contract.

#### U2. Run the same contract on Memory

- **Requirements and dependencies.** R1–R4. Requires U1's backend interface and harness.
- **Affected surfaces.** A Memory backend, a Memory fixture, the profile declaration, and usage documentation.
- **Direction.** Add a host-bound in-memory store. Put file mutations in the store process so create and edit checks apply to the same state as the write. Start a fresh store per exercise and add the profile to the matrix.
- **Proof.** Run the same cases on both profiles. Verify their store observations and cleanup. In a temporary negative check, make a backend acknowledge a write without changing its store and confirm the shared test fails.
- **Completion.** Adding Memory changes the profile declaration and fixture. The shared assertions require no branch for Memory.

### Work Graph

U1 → U2. U1 is the initial frontier. U2 is the integration gate because it proves the interface and suite can take a second backend.

### Verification Contract

Run from the `jido_realm` project root after implementation:

```sh
mix test --only realm_file_contract
mix format --check-formatted
mix test --warnings-as-errors
```

| Gate | Requirements | Evidence |
| --- | --- | --- |
| Live Agent contract | R1, R2 | Both profiles pass every generated case using raw Jido replies and normalized errors. Failures identify the exercise and profile. |
| Backend effects | R3 | The independent observer verifies exact bytes and absence. A temporary no-write backend change causes a failure. |
| Repeatable default suite | R4 | Both fixtures run in fresh stores in the normal suite. The default suite completes without provider credentials or external network use. |

### Rollout and Recovery

Integrate the error mapping and Local expectations in U1. U2 adds a separate profile without a data migration. Future live profiles use explicitly selected ExUnit tests with a unique disposable namespace. If an explicitly selected fixture cannot start, report setup failure. Use bounded provider-side observation if the provider needs it. The agent-visible read after a successful write must still meet the common contract.

### Risks and Assumptions

- Local expects a host-controlled directory. This contract does not establish isolation against unrelated processes that can change that directory while a Realm operation runs.
- File actions perform I/O before the Jido turn commits. A later turn failure can leave a completed change on disk. The first contract covers known success and deterministic file failures. Recovery from an unknown write outcome requires a separate exercise.
- A remote profile must preserve create-only and replace-existing semantics. If a target cannot meet them, the suite must show that gap before the project claims file conformance for it.

### Open Planning Decisions

The first live provider, its fixture lifecycle, and its error and recovery rules are deferred to the project owner. They do not block U1 or U2.

### Definition of Done

Both profiles pass the same public file suite and backing-store observations. Local checks also cover symlinks. The negative check proves that the suite detects a write that never reaches storage. Formatting and the full suite pass. The README shows the contract and how to register another profile.

### Planning Sources

[Current README](../../README.md) · [Plugin admission](../../lib/jido_realm/plugin.ex) · [Action replies and errors](../../lib/jido_realm/file_action.ex) · [Local file operations](../../lib/jido_realm/files/local.ex) · [Current agent tests](../../test/jido/realm_test.exs) · [Elixir requirement](../../mix.exs)

## Adapter Results

- Markdown is the canonical plan.
- HTML and Beadwork were outside this request.
