---
title: Build and edit a Phoenix app with a Jido agent on Apple Container
type: implementation-plan
date: 2026-11-20
last_reviewed: 2026-11-20
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Build and edit a Phoenix app with a Jido agent on Apple Container

## Goal Capsule

Build one Phoenix app in a fresh Realm on this Mac. Then use a Jido AI agent
and local LM Studio to make three successive changes in the same Realm. Run
Mix and the web app in Apple Container. Preserve the accepted diffs, test
results, and browser evidence. This request authorizes the local plan. The
next executor is a Jido Realm developer with authority to implement and run the
local integration case. Stop the live case if the model preflight, the baseline,
or a round fails its acceptance checks.

## Product Contract

### Summary

The host builds the initial Phoenix project. A Jido AI agent then inspects,
edits, and tests that project through tools in three separate turns.

### Problem Frame

The earlier workbench demonstrated that a model could generate complete
projects that served HTTP. This case must show that the model can inspect
an existing project, select edits, interpret test output, and carry the same
working tree through several requests.

### Actors

The host prepares the Realm and sets the tool grants. The agent selects tool
calls. LM Studio supplies local inference. The test harness and a browser
observe the app and the effects of each edit.

### Requirements

- **R1.** Start from an empty Realm. Build a minimal Phoenix Mix project in
  Apple Container and verify that its home page says “Hello, world!”.
- **R2.** Use LM Studio on the Mac. Each edit round must use structured Jido AI
  tool calls to read existing source, change a Realm file, and run a check.
- **R3.** Accept exactly three successive edit rounds in one Realm. Each
  accepted round must preserve the accepted behavior from the earlier rounds.
- **R4.** Save evidence for all four states. Stop the previews and confirm
  cleanup on success, failure, or timeout.

### Key Flows

Open Realm → seed and build the baseline → verify it → send round one → check
and accept it → repeat for rounds two and three → save evidence → close.
The host sends each edit goal in a separate Jido signal. A round can contain
several tool calls and repairs.

### Acceptance Examples

| State | Requested result | Independent proof |
| --- | --- | --- |
| Initial build | Start a minimal Phoenix app in the empty Realm. | Mix tests pass in the guest. The browser shows “Hello, world!”. |
| Round 1 | Add a Jido Realm introduction on the home page. | The browser shows the new intro and the original greeting. The round records a source read, a checked edit, and a successful test call. |
| Round 2 | Add a JSON endpoint at `GET /api/realm` that returns `{"status":"ready"}` and add an app test for it. | An independent HTTP request checks status, content type, and decoded JSON. The home page still passes. The trace records a new test file and production code changes. |
| Round 3 | Give missing pages a Phoenix 404 page with a link home. | The agent runs the new acceptance check before editing and sees it fail. The same check passes after the edit. A browser opens a missing route, follows the link, and sees the Round 1 page. The JSON endpoint still passes. |

### Success Criteria

One live run contains three accepted diffs from real model tool calls in the
same tree. The evidence ties each diff to a guest test result and the expected
HTTP response. Round 3 records a failure and a pass for the same check.

### Scope Boundaries

The case uses one Phoenix app and Apple Container on the local Mac. The
agent and LM Studio run on the Mac. Build, test, and preview commands run in
Apple Container. The host exposes the preview on loopback and owns cleanup.

### Key Decisions

Use a host-authored baseline so that the three scored rounds measure AI
editing. Use the existing model-driven file lane for the opt-in case and
the existing Apple Container example for lifecycle mechanics.

### Rejected Alternatives

The earlier complete-project generation case remains evidence for the initial
build workflow. This case requires tool calls and a separate observed diff
for each change to an existing project.

### Dependencies

Apple silicon, Apple Container, a pinned Linux ARM64 Elixir image, prepared
Hex dependencies, local LM Studio with a tool-capable model, and a browser.

### Outstanding Questions

None identified for this scope. The executor must confirm model readiness
before running the live case.

### Sources

- [Current workbench](../../examples/realm/10_coding_agent_workbench/README.md)
- [Model-driven file integration](../../test/integration/09_model_driven_files/README.md)
- [Apple Container example](../../examples/realm/04_prepare_and_preview_an_app/README.md)

## Planning Contract

### Product Contract Preservation

The direct request sets the platform, local model server, initial build,
tool-driven edits, and three-round sequence. Phoenix and the three edit
tasks are selected fixtures. A seed build precedes the three edit turns.

### Current System

The workbench builds and previews a new Phoenix app through a host-approved
Realm command. Its model returns complete files. The separate live file test
already connects `Jido.AI.Agent` with ReAct tools and verifies the tool
attempts and file bytes. `Jido.Realm.Placement` supplies a Local tree with
revision checks. The Apple example mounts a Realm tree at `/workspace` and
verifies readiness and shutdown on a loopback port.

### Target System

Add one opt-in Apple edit case under `test/integration/09_model_driven_files/`.
Use one managed `:work` session, one fresh project tree and one agent across
all three requests. Retain the same project mount when the host runs a guest
command or restarts the preview. Send the agent a short task and the tool
schemas on each turn. The agent discovers the current source with tools.

### Key Technical Decisions

- **KTD1. Use one host-owned tree and the existing Apple execution path.**
  Seed via Realm file operations. Mount that exact tree at `/workspace` for
  the approved Mix commands and preview. The named-command seam supplies
  build and test execution within this example. This covers R1 and R4 in U1
  and U3.
- **KTD2. Give ReAct explicit file tools and one bounded check tool.** Use
  `list_files`, `read_file`, `replace_text`, `create_file`, and `run_checks`.
  Read returns text and a revision. A replacement requires that revision and
  an exact old text match that occurs once. Apply it through
  `Realm.file/5` with `:edit_revision`. Return a conflict for a stale
  revision and require a fresh read before retry. Create is exclusive and
  scoped to approved app and test paths. Run checks with a fixed input schema
  and approved Mix arguments through `Realm.invoke/4`. Let the agent select
  project checks or the acceptance check for the current round. Return the
  exit status, bounded output, and run ID. This covers R2 in U2 and U3.
- **KTD3. Use a host observer to accept each revision.** Capture a source
  manifest and diff after the agent's tools finish. Keep acceptance checks
  outside the writable project tree and mount them read-only if they run in
  the guest. For Round 3, verify the same check fails and then passes. This
  covers R3 and R4 in U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| Jido action context | The live file test dispatches a typed Realm action from ReAct. | Add example-local tools with schema validation, bounded responses, and traces. | All file reads and writes use the bound Realm. |
| Realm file lease | Local placement supports list, read, create, and checked replacement. | Allow one writer. Serialize mutations and wait for guest commands before admitting edits. | Directory, dependency, lockfile, and acceptance files stay outside the model's write grants. |
| Apple guest | The existing example launches a service from a bind mount. | Mount the same source tree read-only in build, test, and preview guests. Give Mix a separate writable build directory through `MIX_BUILD_PATH`. Prepare pinned dependencies before the edit turns. | Use offline build and test execution after preparation. Limit preview ingress to loopback and record the actual guest network settings. |
| LM Studio | The existing case uses `http://127.0.0.1:1234/v1`. | Use the configured model with the same host client and verify a real read-only tool call and its returned result before the edit turns. | A model list establishes discovery. The tool probe establishes readiness. |
| Evidence | The workbench records logs, source and preview results. | Save the round inputs, accepted diffs, revision hashes, sanitized tool attempts, timings, and evidence under the package's ignored `tmp/` directory. | Keep dependencies and generated test files outside Mix's test discovery paths. |

### Implementation Units

#### U1. Build and observe the initial app

**Requirements** R1 and R4. **Dependencies** None.

Add a Phoenix fixture and an Apple test harness in the model-driven case.
Reuse the Local placement and Apple bind, readiness, and cleanup pattern.
From an empty tree, open the lease and seed the fixture through Realm. Prepare
pinned dependencies, run Mix checks, and start a loopback preview. Prove the
guest reads the seeded source, the host-only sentinel stays outside the
mount, and guest writes to source are denied. Check status and body
independently. Register cleanup before starting each guest resource. This
unit is complete when the baseline passes and the harness can prove that
stopping it closes the listener.

#### U2. Prove the tool path on the built project

**Requirements** R2. **Dependencies** U1 supplies the writable project and
guest command. Add the example-local ReAct actions, schemas, and call trace
using the existing live file test pattern. Check an exact replacement, a
stale revision, an invalid target path, and a failed guest check with its
diagnostic output. A denied write must leave the observer's file bytes
unchanged. Complete this unit when the deterministic checks pass and the
preflight can report whether LM Studio returns a usable tool result.

#### U3. Run the three live turns and save independent proof

**Requirements** R2, R3 and R4. **Dependencies** U2 supplies the tool path
and preflight. Send the three intent-only goals in order. In each trace,
require a source read before mutation and a passing guest check on the final
revision. In Round 3, require the failing acceptance result before the first
mutation. Keep execution and observer results separate from the agent's
summary. Capture the accepted diff, run the cumulative checks, and refresh
the preview from the accepted tree. Complete this unit when the live run has
three accepted revisions, the Round 3 red and green result, and confirmed
cleanup. Add the run instructions to the model-driven case README.

### Work Graph

U1 → U2 → U3. The writable tree and its guest build are prerequisites for
testing the tools. The tool contract and LM Studio preflight gate the three
live turns. U3 is the final integration gate.

### Verification Contract

| Gate | Requirements and units | Evidence |
| --- | --- | --- |
| Baseline | R1, U1 | Fresh tree, guest Mix test exit 0, loopback HTTP 200, browser heading, and listener closure on stop. |
| Tool contract | R2, U2 | Checked replacement, conflict without mutation, path denial, and real guest failure output. |
| Live edit sequence | R2 and R3, U3 | Structured tool calls from LM Studio, three distinct accepted diffs, cumulative tests, Round 3 failure followed by success, and browser checks. |
| Cleanup | R4, U1 and U3 | HTTP listener closed and the named guest resources absent after normal close and a controlled failure. |
| Repository regression | All units | Run the existing package suite and check that the new live case stays opt-in. |

From `jido_realm`, use the package doctor before the live run. The proposed
test file and its exact tag selectors are part of the implementation.
Give the deterministic Apple case the `:apple_container` tag and the live
case the `:lmstudio` tag so each can run on its own.

```sh
mix jido_realm.doctor --lane apple_container --strict
mix jido_realm.doctor --lane lmstudio --strict
mix test test/integration/09_model_driven_files/apple_edit_agent_test.exs --only apple_container
mix test test/integration/09_model_driven_files/apple_edit_agent_test.exs --only lmstudio --max-cases 1
mix test
```

### Rollout and Recovery

Run locally with a disposable tree. Use separate limits for model calls,
tool calls, guest execution, and readiness. On a failed check, return its
output to the same edit turn within those limits. On exhaustion, retain the
failed diff and the last accepted revision for review. Stop the active
guest and check its state before releasing the session. Treat uncertain
cleanup as a failed run and preserve the guest ID for recovery.

### Risks and Assumptions

The model endpoint responded to a read-only discovery request during planning.
The configured model's tool behavior remains an execution preflight. A
successful live run requires LM Studio to return structured tool calls.
A guest process can be alive before it opens its port, so readiness requires
an HTTP probe with its own deadline. The fixture starts with a basic missing
route response so the Round 3 custom-page check has a known red state.

### Open Planning Decisions

None. Before U3, the executor must record the endpoint, model ID, model
preflight result, container image ID, and the timeout limits for the run.

### Definition of Done

The initial build and three successive model-driven rounds pass in one
Apple-backed Realm. The trace and independent observer agree. The final app
preserves the greeting, introduction, and JSON endpoint and handles a missing
page as specified. The browser evidence, diffs, and logs remain available
after the app and its containers stop. The package regression suite passes.

### Planning Sources

- [Realm file and runner API](../../lib/jido_realm.ex)
- [Local placement](../../lib/jido_realm/placement.ex)
- [Checked Local edits](../../lib/jido_realm/files/local.ex)
- [Named command dispatch](../../lib/jido_realm/commands.ex)
- [Live file tool and ReAct configuration](../../test/integration/09_model_driven_files/file_agent_test.exs)
- [Apple Container lifecycle test](../../examples/realm/04_prepare_and_preview_an_app/example_test.exs)
- [LM Studio structured tool calls](https://lmstudio.ai/docs/developer/openai-compat/tools)

## Adapter Results

- Markdown is the canonical plan at this path.
