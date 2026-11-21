---
title: Supervise native Realm services with erlexec
type: implementation-plan
date: 2026-11-20
last_reviewed: 2026-11-20
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Supervise native Realm services with erlexec

## Goal Capsule

Add erlexec as a required Realm dependency. Use it to start and stop a
host-approved native service through the existing preview API. Make the
change and run local checks in `jido_realm`. The executor finishes when the
tests confirm route access and OS process cleanup.

## Product Contract

### Summary

A host can register a trusted native service for an agent. The agent can
request its preview from an open Realm.

### Problem Frame

Realm has a preview adapter for Docker. Its local port manages the Docker
CLI. A native service needs an owner for its OS process group.

### Actors

The host supplies the executable and its options. The agent requests the
approved service. The host gateway authorizes each reviewer.

### Requirements

- **R1.** Require erlexec at build and runtime. Use it for native services.
- **R2.** Grant access to a host-approved service by name. Return its route
  when it is ready.
- **R3.** Revoke access when the service exits or Realm closes. Confirm group
  cleanup before releasing the placement.

### Key Flows

Open Realm, select the approved service, start it, wait for HTTP readiness,
then resolve an authorized route. Stop or close revokes access and stops the
process group.

### Acceptance Examples

An approved service answers on loopback. An invalid start request runs
no command. A child process is gone before close releases the placement.
A startup failure leaves no route. An exit after readiness revokes access.

### Success Criteria

The default test suite uses erlexec and runs the native service integration
tests. Existing Docker previews still pass their lifecycle checks.

### Scope Boundaries

Native services run with the host user's access. Docker and remote providers
own execution inside their environments. The change covers native HTTP
services through the Realm preview interface.

### Key Decisions

The host explicitly configures the service. A process group belongs to the
Realm session. A failed cleanup keeps the placement for host recovery.

### Rejected Alternatives

The existing Docker CLI port controls a provider command. It has no native
group ownership interface for Realm to use here.

### Dependencies

erlexec 2.6 and a supported POSIX host. The native helper needs the
compiler toolchain during dependency compilation.

### Outstanding Questions

None identified.

### Sources

[Realm preview contract](../../lib/jido_realm/preview.ex) ·
[erlexec options](https://hexdocs.pm/erlexec/exec.html)

## Planning Contract

### Product Contract Preservation

The direct request supplies the dependency decision and the trusted-service
boundary. The implementation adds the native binding to the existing API.

### Current System

[Realm](../../lib/jido_realm.ex) checks agent grants.
[Session](../../lib/jido_realm/session.ex) holds the lease and preview handle.
[Docker](../../lib/jido_realm/runner/docker.ex) uses Docker to confirm stop.

### Target System

A native adapter uses literal host-configured arguments and erlexec group
ownership. A BEAM process monitors the session and gathers bounded startup
output. The gateway resolves the route only while the managed leader runs.

### Key Technical Decisions

- **KTD1.** Declare erlexec in the package manifest and qualify the pinned
  release. This satisfies R1 and U1.
- **KTD2.** Use `:native` as a preview selector. Accept a configured name and
  bounded start time. Keep executable, arguments, directory, and loopback
  port under host control. This governs R2 and U2.
- **KTD3.** Confirm group absence independently after stop. Treat uncertain
  cleanup as an error, deny the route, and keep the existing handle for retry.
  This governs R3 and U2.

### System Boundaries and Change Surface

| Surface | Change | Compatibility |
| --- | --- | --- |
| Mix manifest and locks | Add erlexec and update the qualification locks. | Hosts must build the native helper. |
| Realm and Preview | Add a native selector and a liveness check for adapters that support it. | Existing preview callbacks remain valid. |
| Session and OS | Monitor native ownership and verify group cleanup before release. | Providers continue to own their workloads. |

### Implementation Units

- **U1. Dependency.** Fetch and compile erlexec from Hex in the Realm package.
  Verify dependency resolution in both qualification projects.
- **U2. Native lifecycle.** Add the adapter, integrate it with Session, and
  add real lifecycle tests. Depends on U1 for execution.
- **U3. Verification and usage.** Run the focused and provider tests and
  document host configuration. Depends on U2.

### Work Graph

U1 supplies the compiled dependency to U2. U2 supplies the service lifecycle
to U3. U1 is the initial unit.

### Verification Contract

Run the following commands from the Realm package root.

```sh
mix test test/integration/05_services_and_routes/native_preview_test.exs
mix test
mix test --include docker --include browser
```

| Requirement | Test evidence |
| --- | --- |
| R1 | Dependency compile and application startup. Qualification projects still resolve. |
| R2 | A live agent starts a fixed service. An HTTP client reads its response. Unauthorized requests and invalid options fail. |
| R3 | Observe child exit and port closure. Test startup failure, spontaneous exit, and loss of the session owner. Verify Docker preview lifecycle. |

### Rollout and Recovery

The host selects a trusted command and reserves its loopback port before
use. If Realm cannot confirm cleanup, inspect the service and retry close
after its group stops.

### Risks and Assumptions

The native tool and its executable inputs come from the host. The service
uses the assigned loopback address and keeps children in its process group.
Linux and macOS can report a group present while children await reaping.

### Open Planning Decisions

None identified.

### Definition of Done

Realm compiles and starts with erlexec. The tested native preview starts
only the configured command, checks readiness, revokes routes, and confirms
cleanup before releasing the lease. Existing preview adapters pass their
regression tests. The README gives a working configuration.

### Planning Sources

[Workspace process-group example](../../examples/04_sandboxes_toolchains_and_services/04_03_supervise_a_native_process/README.md) ·
[Realm integration ladder](../../test/integration/README.md)

## Adapter Results

- Markdown is the canonical plan.
- HTML and Beadwork were outside the request.
