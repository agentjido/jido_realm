---
title: Unify Realm with standalone Shell and VFS
type: implementation-plan
date: 2026-11-21
last_reviewed: 2026-11-21
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Unify Realm with standalone Shell and VFS

## Goal Capsule

Build and verify one local Realm candidate. Use the existing Git history and
move the shared capabilities into Realm. Keep Shell and VFS as their own OTP
applications and source repositories. The local assignment ends with verified
working trees. The owner controls the GitHub rename and publication.

## Product Contract

### Summary

Realm gives an agent a place to edit files, run tools, and preview results.
The host controls provisioning, grants, recovery, and deployment.

### Problem Frame

The earlier candidate embeds duplicate Shell and VFS source. It also exposes
the host workflows under the former project identity.

### Actors

The host configures and opens a Realm. An agent works in it with scoped
grants. A reviewer can reopen the saved result with read-only authority.

### Requirements

| ID | Requirement |
| --- | --- |
| R1 | Ship one Realm package and public namespace. Keep the host interface under Realm and remove the former project identity from the current checkout. |
| R2 | Use standalone Shell and VFS packages, each with its own OTP application, source, and tests. |
| R3 | Preserve the 45 numbered examples and 19 additional example files. Preserve the Realm examples and supported integration checks. |
| R4 | Preserve one shared tree and lease for the native provider, checked saves and previews, snapshot reopening, host recovery, and deployment. |
| R5 | Prepare the existing repository for an in-place GitHub rename. The current authorization is for local changes and checks. |

### Key Flows

The host selects a profile and provider. Agent file and command calls share
the provider's tree. The host can reopen a saved result in a fresh BEAM and
can recover a prior command without acquiring a new write lease.

### Acceptance Examples

Run the live Docker edit and check, inspect the resulting file through Realm,
save the verified tree, and reopen it from a read-only agent. Run the stale
writer, lost launch reply, and OTP deployment examples.

### Success Criteria

A clean consumer boots all three OTP applications and builds an OTP release.
All 64 imported examples pass with their fixtures. The checkout and generated
docs use the Realm identity.

### Scope Boundaries

Provider behavior and durable reference formats retain their tested contracts.
Separate work covers remote changes, a history rewrite, and Hex publication.

### Key Decisions

Keep the agent API in `Jido.Realm` and put privileged operations under
`Jido.Realm.Host`. A shared checkout uses the host controller under the Realm
provider lease.

### Rejected Alternatives

Retiring host capabilities or installing a second copy of Shell or VFS would
break the example and package contracts.

### Dependencies

The standalone VFS tree already has atomic captures. Move the tested atomic
working-tree operations into that tree. Move the literal argument entry
point into Shell. For local checks, select the local packages with
`JIDO_SHELL_PATH` and `JIDO_VFS_PATH`.

### Outstanding Questions

The first Hex version and publication date are owner decisions. Future Git
installation from public refs requires the compatible dependency revisions.

### Sources

[Realm agent API](../../lib/jido_realm.ex), [examples](../../examples/README.md),
and the local standalone Shell and VFS Git trees.

## Planning Contract

### Product Contract Preservation

Product Contract unchanged from the approved merge scope.

### Current System

The shared checkout provider delegates file, run, and save operations to
the host controller. The app currently starts two copied supervisors.
Shell lacks the literal argument call used by the host memory provider, and
standalone VFS lacks the working-tree call used for atomic edits.

### Target System

The agent session uses `Jido.Realm.Provider.SharedCheckout` to open a
`Jido.Realm.Host` handle. Host and agent share one provider lease. OTP starts
Shell and VFS as dependencies. Realm starts its own registries and services.

### Key Technical Decisions

- **KTD1.** Keep trusted host profile and policy types distinct from agent grants.
  Share the host controller at the provider boundary. (R1, R4)
- **KTD2.** Place adapter operations and literal argument dispatch in their
  respective packages. Keep provider integration in Realm. Resolve the same
  VFS source in Shell and Realm. (R2, R3)
- **KTD3.** Change Elixir namespaces, package identity, and both sides of the OTP
  deployment RPC in one local candidate. Preserve format-1 data and behavior.
  (R1, R3, R4)
- **KTD4.** Use Git dependencies for the first GitHub cutover. Keep Hex
  packaging as a separate release check. (R2, R5)

### System Boundaries and Change Surface

| Surface | Change and verification |
| --- | --- |
| Application and dependencies | Realm starts its own supervisor. Confirm the module owner for each dependency. |
| Provider and file tree | Keep checked writes and batches atomic. Verify saves, grant denials, and same-tree execution. |
| Retention and deployment | Preserve file bytes and reference format. Update target RPC calls and the Erlang module together. |
| Examples and docs | Keep the 64-file inventory with original assertions. Update the API calls and published entry points. |

### Implementation Units

- **U1. Standalone contracts** (R2, R3). Port atomic working-tree operations
  and literal Shell arguments. Check compile and the package suites before
  integrating. No unit dependency.
- **U2. Realm integration** (R1, R2, R4). Depend on both packages. Move host
  modules and deployment RPC to Realm. Remove duplicate source, supervision,
  and config fallbacks. Run focused host, agent, and file checks. Depends on U1.
- **U3. Clean checkout and full proof** (R1, R3–R5). Migrate docs and examples,
  verify identity removal and file inventory, run all example lanes, and
  install and boot from an isolated consumer. Depends on U2.

### Work Graph

U1 → U2 → U3. U3 is the local delivery check.

### Verification Contract

| Gate | Commands and expected evidence |
| --- | --- |
| U1 | Run `mix test` in Shell and VFS with the selected VFS source. |
| U2 | Run `mix format --check-formatted` and `MIX_ENV=test mix compile --warnings-as-errors` in Realm. |
| U3 | Run `mix test`, `MIX_ENV=test mix test.integration --include s3 --trace` with Docker, Apple Container, and MinIO, and `MIX_ENV=test mix test.realm --include docker --include browser --include apple_container --max-cases 1`. Compare the trace with the 64-file inventory. |
| U3 | From a separate consumer, run `mix deps.get` and `mix release`, inspect OTP module ownership, and run the shared Docker handoff. |

### Rollout and Recovery

Keep the current remote and Git history during local work. Retain earlier
planning records outside the candidate checkout. Before a later rename,
confirm the target name, dependency refs, canonical URL, repository ID, and
required CI. Close legacy placements and confirm provider release before
switching runtime versions. Docker labels and the target RPC use the Realm
identity. Keep persistent machine and command references for host recovery.
If an example or consumer fails, repair the affected candidate
and rerun the check. Keep stored references and lease records for recovery.

### Risks and Assumptions

A clean app start can conceal one copied module or a mismatched VFS source.
Check module ownership and dependency resolution in a separate consumer.
The example lanes need local runtimes. Report unavailable lanes and any
difference between live gVisor execution and runtime-unavailable admission.

### Open Planning Decisions

The owner controls upstream merges, the remote rename, exact public dependency
refs, and release publication. The local candidate can use source paths.

### Definition of Done

Realm has one unified identity, separate Shell and VFS dependencies, an
isolated consumer and release proof, and passing suites for the migrated
examples and Realm behaviors.

### Planning Sources

[Mix project](../../mix.exs), [Realm examples](../../examples/realm/README.md),
and the Git base with the 64-file example inventory.

## Adapter Results

Markdown is the canonical plan.
