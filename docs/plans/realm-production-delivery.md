---
title: Jido Realm v1 roadmap
type: implementation-plan
date: 2026-11-20
last_reviewed: 2026-11-20
artifact_contract: kata-plan/v1
artifact_readiness: planning-blocked
domain: software
execution: code
product_contract_source: realm-compatibility-scope
---

# Jido Realm v1 roadmap

## Goal Capsule

Release Jido Realm 1.0 with a stable API and a verified path from editing a
checkout to showing the result. Prove that path on Docker and, subject to
owner approval, on one hosted provider. Run dependency and packaging work
in parallel. Use evidence to advance each milestone.

This plan covers local planning. The Realm maintainer can start capability
admission and dependency qualification once implementation is authorized.
The full v1 boundary needs the [owner decisions](#open-planning-decisions).

| Milestone | Result | Exit gate |
| --- | --- | --- |
| Developer preview | A coding agent repairs and tests a checkout on Docker. The doctor explains unmet profile requirements. | Same-tree case passes independently of test fixture cleanup. Capture package resolution evidence in a fresh consumer. |
| Beta | A reviewer can open a saved HTML bundle and a private endpoint. A second agent can reopen retained work. | The bundle matches the tested revision. Route revocation and recovery pass under controller loss. |
| Release candidate | The agreed provider matrix works through the same agent API. Consumer installation uses the proposed release dependencies. | Every supported claim has matching evidence. Existing callers pass after migration. Operators can reproduce the install and recovery steps. |
| 1.0 | Supported APIs, Signals, errors, host profiles, and data lifetimes are documented and versioned. | The owner approves the supported matrix and the exact candidate passes the release gates. |

## Product Contract

### Summary

Realm gives a Jido agent a scoped place to work. The host selects providers,
access, and retention. The agent uses the same calls when its profile meets
the requirements for the job.

### Problem Frame

The current package can demonstrate most steps of the coding workflow in
isolation. The Docker runner stages inputs read-only. The saved presenter
keeps output in memory. The hosted workflow has no equivalent live
evidence yet.

### Actors

- The coding agent reads, edits, tests, and publishes the result.
- The host operator supplies bindings and grants and handles recovery.
- The reviewer opens saved output or an approved live endpoint.

### Requirements

| ID | Requirement |
| --- | --- |
| R1 | Admit the job only if the binding and the caller's grants cover all required operations. Report the same effective capabilities through Realm and the doctor. |
| R2 | Give the agent and the toolchain the same writable tree. Tie a passing test and its handoff to a source revision. |
| R3 | Give a reviewer independent access to versioned saved output and a live endpoint. Permit a route to an approved listener that Realm did not start. |
| R4 | Let a second authorized agent reopen retained source, output references, and the setup recipe. Confirm ownership before another writer can resume work. |
| R5 | Apply the same contracts to each supported binding. Record live evidence for each advertised hosted capability. |
| R6 | Install and use the versioned package from a separate Jido project. Keep a migration path for existing Realm callers. |

### Key Flows

Open a named Realm, edit and test the checkout, publish a saved bundle, and
optionally expose a running service. Revoke the route, close the Realm, and
reopen retained work under a new lease.

### Acceptance Examples

A known failing test passes after the agent fixes the code. A reviewer can
use the resulting HTML after the source changes and the Realm closes. Two
Realms can expose the same guest port. Revoking one URL leaves both services
running. After controller loss, an authorized agent reopens the retained
revision and a stale writer cannot change it.

### Success Criteria

Run the same acceptance job against each supported coding profile. Verify
the file bytes, test revision, browser result, endpoint identity, and
cleanup with independent observers. Publish the support matrix with the
exact scope and limits of each claim.

### Scope Boundaries

Keep Local, Realm Memory, VFS Memory, Lua, and trusted native services on
the release path. Use Docker as the reference coding backend. Propose
Sprites as the first hosted backend, using the Elixir SDK published as
`sprites`. Treat a host-approved Git checkout as a reference workload.

Keep Apple Container, E2B, Daytona, S3, GitHub, and the other VFS bindings
in the compatibility matrix. They can qualify in parallel and join the
support list after their own cases pass. Direct Fly Machines support is out
of scope. Continuous process resume, raw TCP, and public sharing are
separate claims. Private HTTP and durable work are the proposed v1 defaults.

### Key Decisions

Retain one public `Jido.Realm` API. Keep `erlexec` as the mechanism for
trusted native services. Use separate operations for managed services,
endpoint access, and saved output.

### Rejected Alternatives

A provider-specific agent API would make the coding job depend on the
deployment. Publishing provider URLs directly can also couple authorization
to provider-wide settings.

### Dependencies

Realm uses Jido, Jido VFS, `erlexec`, and the Sprites SDK. See the
[dependency manifest](../../mix.exs). The hosted cases need a dedicated
account and approved test limits.

### Outstanding Questions

The maintainer must confirm the hosted release gate, the supported host and
Elixir/OTP matrix, and the test-account limits before issuing the release
candidate. The [open planning decisions](#open-planning-decisions) show the
work each decision controls.

### Sources

[Product vision](../../VISION.md) · [Compatibility scope](realm-compatibility-scope.md) ·
[Integration ladder](../../test/integration/README.md)

## Planning Contract

### Product Contract Preservation

The existing delivery plan's five work areas remain in scope. Admission
maps to U1, Docker to U3, presentation to U4 and U5, recovery to U6, and
provider qualification to U7 and the compatibility matrix. U2 and U8
make package delivery explicit. The milestones propose when to qualify
each area.

### Current System

- Local and Memory have real file coverage. VFS Memory has basic conformance
  through the checked VFS path. S3 and GitHub use controlled transports.
  [Files and transfer](../../test/integration/01_files_and_transfer/README.md)
- Docker runs Bash, Python, and JavaScript from staged inputs. Native preview
  runs through `erlexec`. The current facade couples preview start to route
  setup, and saved output uses an in-memory presenter. [Docker runner](../../lib/jido_realm/runner/docker.ex) ·
  [Native preview](../../lib/jido_realm/preview/native.ex) · [Artifacts](../../lib/jido_realm/artifacts.ex)
- The Sprite binding provides approved reads and owned and borrowed
  lifecycle evidence through a controlled transport. The doctor reports
  local preflight by lane. The recorded macOS run passed 154 tests with
  Docker and browser enabled. It excluded four Apple Container, live
  Sprite, and LM Studio tests. [Sprite adapter](../../lib/jido_realm/provider/sprite.ex) ·
  [Doctor usage](../../README.md#check-host-and-test-prerequisites) · [Recorded evidence](realm-compatibility-scope.md#coverage-and-acceptance)

### Target System

The session combines binding capabilities, profile requirements, and grants.
It admits the job and binds the runner to the managed file tree. The
presenter saves a verified revision. The gateway issues a revocable grant
for an approved endpoint under the current lease. The host reconciles
placement and ownership after interruption.

### Key Technical Decisions

- **KTD1. One admission contract.** Use one effective capability calculation
  for session admission and profile diagnostics. Keep host prerequisites
  visible as separate doctor findings. This governs R1 and U1.
- **KTD2. One working tree.** Expose the same managed tree to file operations
  and process execution. Prove same-tree behavior by observing changes in
  both directions. A staged runner continues to report its staged mode.
  This governs R2 and U3.
- **KTD3. Separate lifetimes.** Use service, endpoint, and saved-output handles.
  An endpoint grants access to a bound target. A saved bundle records one
  tested revision and has its own retention policy. This governs R3 and U4–U6.
- **KTD4. Recovery before write access.** Separate Realm identity, placement,
  and lease. Withhold a new write lease while an old writer may still be
  active. Recover work from confirmed state and start a new service when
  needed. This governs R4 and U6–U7.
- **KTD5. Qualify the package as a consumer uses it.** Test released
  dependencies and one downstream install. Use the same acceptance job
  across the release matrix. This governs R5–R6 and U2, U7, and U8.

### System Boundaries and Change Surface

| Boundary | Planned contract |
| --- | --- |
| Agent and host | Stabilize documented facade calls, Signals, result fields, error codes, and profile semantics. Add new calls alongside current calls during beta. Track adapter callbacks separately in the documented support contract. |
| Files and execution | Keep rooted paths, checked revisions, bounded output, and explicit modes. Record the operation and the last verified state if execution or a mutation has an unknown outcome. |
| Data and access | Record the tested source revision, bundle revision, ownership, and retention. The host controls credentials, sandbox grants, and viewer access. Isolate active HTML from the host application's origin and credentials. |
| Providers and packages | Use provider-specific operations behind the same Realm contract. Qualify each provider's toolchain, access, and retention. Keep provider account setup under the operator's control. |

### Implementation Units

#### U1. Effective capabilities and doctor profiles

R1 · KTD1. Starts now once authorized. Extend [Profile](../../lib/jido_realm/profile.ex),
[Session](../../lib/jido_realm/session.ex), and [Doctor](../../lib/jido_realm/doctor.ex).
Use granular file, execution, endpoint, and retention claims. Preserve
existing grants. Pass 02.03 with a read-only binding and show why a coding
profile fails admission before it makes a change.

#### U2. Clean dependency resolution and package build

R6 · KTD5. Starts in parallel with U1. Qualify published Jido and Jido VFS
versions against the exact DSL and checked file APIs Realm uses. Hex lists
Jido 3.0.0-beta.3 as a candidate. Matching a version string does not prove
that it has the API from the current Git pin. Check `capture/1` and
`apply_edits/3` on the VFS release. Resolve the Sprites/Cowlib constraint
with the upstream SDK. Add package metadata, a license, changelog,
HexDocs, and Jido's standard CI. Build the package and resolve it in a
fresh consumer without dependency overrides. [Jido package](https://hex.pm/packages/jido) ·
[Sprites package](https://hex.pm/packages/sprites) · [Hex requirements](https://hex.pm/docs/publish#dependencies)

#### U3. Coding agent on a writable Docker tree

R2 · KTD2. After U1. Extend the [Docker runner](../../lib/jido_realm/runner/docker.ex)
and the [coding job](../../test/integration/08_composed_jobs/08_02_build_test_and_hand_off/README.md).
Exercise an approved Git checkout. Run setup and a failing test, repair it,
and verify the passing test and revision. Observe tool and agent writes
from both sides. Prove process stop, resource limits, and cleanup on
interruption. Run 03.01, 03.02, 03.05, 04.01–04.05, and 08.02.

#### U4. Verified saved output

R3 · KTD3. After U1. Extend [Artifacts](../../lib/jido_realm/artifacts.ex)
and add `Jido.Realm.publish`. Take one checked revision of the bundle. Keep
versioned output behind the presenter under its own retention policy.
Keep `publish_artifact` available during migration. Run 08.03 in a browser
and verify access denial, conflicting source changes, and the exact saved
bytes after close. Verify that generated scripts cannot access the host
application's session.

#### U5. Services and endpoints

R3 · KTD3. After U3. Extend the [preview boundary](../../lib/jido_realm/preview.ex)
with `start_service`, `stop_service`, `expose`, and `unexpose`. Map
existing preview calls through a compatibility path. Qualify private HTTP
on Docker and trusted native services. Test a listener that Realm did not
start. Run 05.01–05.02 and 08.01. Use two Realms on the same guest port and
verify route identity, revocation, startup failure, and lease cleanup.
Run 05.03 separately when a profile claims temporary public sharing.

#### U6. Durable reopen and recovery

R4 · KTD3–KTD4. After U3, U4, and U5. Extend [Session](../../lib/jido_realm/session.ex),
placement, and presenter storage to persist source identity, setup, output,
and ownership. Exercise lost open, run, and stop replies. Confirm that a
new controller can recover a single placement, reject a stale writer, and
revoke old access. Require 06.02, 07.01, 07.05, and the safety checks from
07.04. An unknown prior run must block another writer. Retrying must avoid
a duplicate launch. Require the full 07.04 run reattach case if the release
promises it. Use 07.02 for snapshot restore and 07.03 for prepared-state
resume when claimed. Verify reopened source and output against the tested
revision.

#### U7. Hosted provider parity

R5 · KTD4–KTD5. After U6 and approval of the hosted provider. Extend the
[Sprite provider](../../lib/jido_realm/provider/sprite.ex) with the
Elixir SDK if the owner accepts Sprites. Start with live owned and
borrowed lifecycle and add writable files, execution, private routes, and
retained reopen in that order. Use 06.04 for lifecycle, 03.05 for stop,
05.01–05.02 and 08.01 for private ingress, 07.01 for retained reopen, and
08.02–08.03 for the coding job and browser handoff. Verify target identity,
ownership, cleanup, and route behavior after idle and wake in a dedicated
account. The existing lifecycle case can run as soon as the owner approves
the test account and limits.

#### U8. Release candidate and 1.0 gate

R1–R6 · KTD5. After U2, U6, and U7 under the proposed hosted gate. Run the
complete job from a fresh consumer. Verify migration wrappers, install
instructions, operation at the supported version floor, and the operator
recovery procedure. Document each stable call and provider claim. Record
the approved release scope and evidence for the exact candidate.

### Work Graph

Start U1 and U2 in parallel. U3 and U4 can proceed after U1. U5 follows U3.
U6 joins U3, U4, and U5. U7 uses the finished recovery contract. U8 combines
the dependency and product tracks. Keep provider work outside the proposed
v1 gate on the existing compatibility matrix.

### Verification Contract

Pass the [required binding cases](../../test/integration/README.md#required-binding-cases)
for every profile in the release matrix. Run these commands from the Realm
package root. Run live cases with the approved account and test limits.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix jido_realm.doctor --lane docker --format json --strict
mix test --include docker --include browser --warnings-as-errors
```

| Check | Requirements | Evidence |
| --- | --- | --- |
| Admission and preflight | R1 | Case 02.03, true prerequisite reports, existing caller contracts. |
| Coding and isolation | R2 | Cases 03.01, 03.02, 03.05, 04.01–04.05, 08.02. Independent checks of changes, tested revision, and process stop. |
| Reviewer experience | R3 | Cases 05.01–05.02, 08.01, 08.03. Browser interaction and independent requests before and after revocation and close. |
| Recovery | R4 | Baseline cases 06.02, 07.01, 07.05, and the 07.04 safety checks. Claim-specific cases in U6. Controller loss, second agent, exact retained bytes, and stale lease denial. |
| Provider and release | R5–R6 | Live conformance for each hosted claim, a package build, and a tested clean consumer at the agreed floor. Record scope, host, versions, and test outcome. |

Run the [LM Studio/Qwen pressure test](../../test/integration/09_model_driven_files/README.md)
after deterministic conformance. Use the results to assess the agent's tool
use.

### Rollout and Recovery

Offer the beta to an approved consumer first. Keep the prior artifact and
preview entry points available until migration tests and release notes are
ready. Record placement IDs, lease states, stop outcomes, and revocations
without credentials or access URLs. Halt promotion if routing crosses a
Realm boundary, a stale writer can change work, or cleanup is unconfirmed.
Revoke access, reconcile resource ownership, and verify the retained
revision before another lease starts.

### Risks and Assumptions

The current Git pins block Hex publication. The lock also shows that
`sprites` 0.2.4 constrains Cowlib to the 2.19 series while Realm overrides
to 2.22. A successful local test with the override does not prove downstream
resolution. A supported hosted binding needs matching lifecycle evidence.
[Lockfile](../../mix.lock) · [Hex requirements](https://hex.pm/docs/publish#dependencies)

### Open Planning Decisions

| Owner | Decision | Affected work |
| --- | --- | --- |
| Realm maintainer | Confirm that 1.0 requires one live hosted coding backend. Sprites is the proposed choice. Confirm the dedicated account and cost limits. | U7 and the final supported matrix in U8. |
| Realm maintainer | Select the supported OS, architecture, and minimum Elixir/OTP combinations from clean build evidence. | Final CI and the U8 release gate. |
| Realm maintainer | Confirm the recovery promise. The proposal retains source, published output, and setup through controller restart. Process resume requires a separate supported claim. | The durable contract in U6 and recovery gates in U8. |
| Realm and upstream maintainers | Confirm which published Jido and VFS releases satisfy the checked APIs and how the SDK constraint is resolved. | U2 can start now. Its result gates U8. |

### Definition of Done

The agreed support matrix passes at the release candidate version. A clean
consumer can install Realm, repair and test a real checkout, open the saved
HTML, and revoke a live route. A second agent can reopen the verified work.
The stable API, capability limits, migration steps, and recovery procedure
are documented. Every release claim has matching evidence.

### Planning Sources

[Existing compatibility scope](realm-compatibility-scope.md) ·
[Package manifest](../../mix.exs) · [Public API](../../lib/jido_realm.ex) ·
[Integration ladder](../../test/integration/README.md)

## Adapter Results

Markdown is the canonical plan.

## Local coding workflow implementation

The host binds an agent's `:program` Realm to a Memory session and an
artifact store. The agent uses the Realm signals to open the session, change
files, run a program, save an HTML bundle, and close the session.

1. Add the open, close, and artifact signals to the existing plugin. Use the
   same grant checks as the action API.
2. Add a host-selected Docker mode that loads declared files into tmpfs.
   A successful run can return declared output files through checked writes.
   Keep the existing read-only runner for hosts that select it. Lua runs on
   the BEAM with its existing file mediation.
3. Exercise all four runtimes through a Jido agent with a Memory placement.
   Open a saved, interactive HTML bundle in Chrome after the session closes.
   Run the package suite with Docker, the browser lane, and a 90% line target.
