# Jido Realm integration ladder

Each numbered folder describes one agent job. Use the case notes and
test tags to identify the bindings that have runnable evidence. The [Vision](../../VISION.md) defines the architecture.
The [runnable examples](../../examples/realm/README.md) provide current evidence
for later chapters. The [live Qwen file test](09_model_driven_files/README.md)
checks the same file boundary with a model that selects its own tool calls.
The [Workspace example ladder](../../examples/README.md)
is the reference for this structure.

```sh
mix test test/integration
```

The `realm_case` macro in `test/support/conformance/scenarios.ex` runs
one job and its assertions for each named set of bindings. A binding can
pass options to its fixture, such as owned or borrowed placement, file
grants, or an interrupted write. The agent declares its Realm names and
Profiles in its `realms` DSL. The fixture prepares the host bindings,
registers cleanup, and provides an independent observer. An optional seed
callback writes fixture inputs before the job. The agent opens and closes
managed bindings through Realm.

Local and Memory use real stores. The S3 and GitHub cases use controlled
transports to check the Realm side of their contracts. Live service
verification requires the corresponding provider transport and test
account.

Each test name shows its binding and evidence type. `--only realm_case`
selects the default variants. Three variants run the same note and copy
cases against VFS Memory in the main suite.
The [program execution chapter](03_program_execution/README.md) also has
opt-in Docker runs for Bash, Python, and JavaScript. The
[file confinement case](04_sandbox_and_setup/04_01_confine_code_to_approved_files/README.md)
runs a complete Node report job in Docker and checks its file and process boundary.

## Coding and artifact cases

These 20 scenarios extend the ladder. A scenario can run on more than
one binding. The browser and Docker variants are opt-in.

| Scenarios | What they check |
| --- | --- |
| 9 [HTML artifact](08_composed_jobs/08_03_publish_and_show_an_html_artifact/README.md) | Selected files, version retention, publish and read grants, missing assets, path validation, revocation, bundle limits, and browser interaction. |
| 2 [Coding agent](08_composed_jobs/08_02_build_test_and_hand_off/README.md) | Repair and publish a verified report. Block the handoff when verification still fails. |
| 3 [Transfer guarantees](01_files_and_transfer/transfer_guarantees_test.exs) | Preserve a move source after destination verification fails, stream a 3 MiB binary, and allow one writer to win a copy race. |
| 2 [Provider runners](06_provider_lifecycle/06_01_add_a_provider/provider_runner_test.exs) | Run a toolchain supplied by a provider and honor the host's selection when an override is unavailable. |
| 2 [Mediated build](04_sandbox_and_setup/mediated_build_test.exs) | Read only declared inputs and preserve the last good build when Lua exceeds the draft budget. |
| 1 [Lost open reply](06_provider_lifecycle/06_02_recover_a_lost_open_reply/lost_open_test.exs) | Recover one placement with a controlled provider that supports idempotent open. |
| 1 [Retained work](07_retention_and_recovery/07_01_reopen_work_with_another_agent/retained_work_test.exs) | Open a retained tree for a second, read-only agent and reject writes from the closed session. |

## Added coverage

| Case | Runnable evidence | Open variants |
| --- | --- | --- |
| [03.02 Build and test](03_program_execution/03_02_build_and_test_with_a_toolchain/README.md) | Docker runs a test, compiles Python bytecode, and runs the saved binary from Realm. | Native and Wasm builds, stale inputs. |
| [03.04 Observe a run](03_program_execution/03_04_observe_a_background_run/README.md) | Lua on Local and Memory reports progress and a result under one run ID. | Other runtimes and history across sessions. |
| [03.07 Invoke a command](03_program_execution/03_07_invoke_a_host_approved_command/README.md) | Local and Memory run a host-approved command with checked arguments and scoped reads. | Embedded runtime bridge. |
| [04.02 Network access](04_sandbox_and_setup/04_02_control_network_access/README.md) | Docker verifies a request reaches a peer only on the approved internal network. | Apple Container and remote provider controls. |
| [04.05 Setup](04_sandbox_and_setup/04_05_prepare_an_environment/README.md) | Lua on Local and Memory publishes setup output only after success. A later run reads it. | Native setup within the container workspace. |
| [05.01–05.03 Routes](05_services_and_routes/README.md) | Docker and a local gateway check readiness, failed start, stop, private access, and temporary HTTPS access. Native services verify process-group cleanup with erlexec. | Ingress that enforces a lease independently of the Realm controller. |
| [06.04 Sprites](06_provider_lifecycle/06_04_allocate_or_reuse_a_sprite/README.md) | The Elixir SDK runs the owned and borrowed lifecycle case against a controlled transport. | Run the same case with a Sprite test token. |
| [08.01 Copy and preview](08_composed_jobs/08_01_copy_and_preview_on_a_sprite/README.md) | Docker serves the copied HTML and a later revision. The test checks file bytes, access, and cleanup. | Sprite preview and the repository review and test cycle. |

Run the Docker and browser cases with `mix test --include docker --include browser`.
The default suite runs the Sprite lifecycle case with a controlled transport.
See the [Sprite lifecycle case](06_provider_lifecycle/06_04_allocate_or_reuse_a_sprite/README.md)
for the live test command.

## Chapters

| Chapter | First result to prove | Cases |
| --- | --- | --- |
| [00 Profiles and Realms](00_profiles_and_realms/README.md) | Give one agent a named place to work. Verify separate instances and close while work is active. | 4 |
| [01 Files and transfer](01_files_and_transfer/README.md) | Give the agent a predictable file tree and a safe way to transfer work between places. Verify object and branch semantics on remote file bindings. | 8 |
| [02 Policy and admission](02_policy_and_admission/README.md) | Establish host authority and reject unmet requirements before running untrusted code. | 3 |
| [03 Program execution](03_program_execution/README.md) | Run agent-authored programs and invoke host-approved commands. | 7 |
| [04 Sandbox and setup](04_sandbox_and_setup/README.md) | Prove isolation, mount grants, and the controls that apply to setup. | 7 |
| [05 Services and routes](05_services_and_routes/README.md) | Let an agent serve its work for review. Verify readiness and the lifetime of each route. | 3 |
| [06 Provider lifecycle](06_provider_lifecycle/README.md) | Verify allocation, attachment, and release on local and remote bindings. | 5 |
| [07 Retention and recovery](07_retention_and_recovery/README.md) | Preserve work across sessions and recover uncertain runs without admitting conflicting writers. | 5 |
| [08 Composed agent jobs](08_composed_jobs/README.md) | Fix and test a repository, show a saved HTML artifact, and preview a running application. | 3 |
| [09 Model-driven files](09_model_driven_files/README.md) | Give a Qwen-backed Jido AI agent file tools for Local and Memory Realms. | 1 |

## Build order

1. **One place, then two.** Run the note job on Local and Memory. Open and close through Realm, including close during an active write. Prove file grants and path confinement, then copy in both directions. [Profiles and Realms](00_profiles_and_realms/README.md) · [Policy and admission](02_policy_and_admission/README.md) · [Copy](01_files_and_transfer/01_03_copy_between_realms/README.md)
2. **One whole program.** Check capability admission, then write, run, and repair the program through Realm with mediated Lua. Verify the file boundary and staged writes. [Admission](02_policy_and_admission/02_03_require_a_verified_capability/README.md) · [Program loop](03_program_execution/03_01_write_run_and_revise/README.md) · [Staged output](03_program_execution/03_03_publish_staged_output/README.md) · [File boundary](04_sandbox_and_setup/04_01_confine_code_to_approved_files/README.md)
3. **Show a saved result.** Publish the same HTML bundle from Local and Memory. Verify that a reviewer can open and use it, that access is scoped to the bundle, and that the saved copy survives session close under its retention policy. [HTML artifact](08_composed_jobs/08_03_publish_and_show_an_html_artifact/README.md)
4. **First coding agent.** On Docker, fix and test a repository through Realm and show its HTML output through the same artifact contract. Verify the toolchain, writable tree, file boundary, and release on close. [Build and test](03_program_execution/03_02_build_and_test_with_a_toolchain/README.md) · [Coding job](08_composed_jobs/08_02_build_test_and_hand_off/README.md)
5. **Preview the running application.** Copy a page from Local and serve the exact bytes through a private preview on Docker. Verify readiness, access, failed start, and stop. [Private preview](05_services_and_routes/05_01_start_a_private_preview/README.md) · [Copy and preview](08_composed_jobs/08_01_copy_and_preview_on_a_sprite/README.md)
6. **Repeat on other providers.** Run the coding and preview jobs on Apple Container and Sprites. Start with a borrowed Sprite and verify that close preserves it. Exercise fresh allocation under a separate grant. A new provider qualifies by running the same cases for the capabilities it offers. [Sprite lifecycle](06_provider_lifecycle/06_04_allocate_or_reuse_a_sprite/README.md)
7. **Additional bindings and claims.** S3 and GitHub can advance after the file cases. Wasm can advance after the program loop. Add setup reuse, public ingress, durable handoff, snapshots, and recovery where the binding requires them. [Files](01_files_and_transfer/README.md) · [Setup](04_sandbox_and_setup/README.md) · [Public route](05_services_and_routes/05_03_publish_a_temporary_route/README.md) · [Recovery](07_retention_and_recovery/README.md)

Chapter numbers group related behavior. Use **Build on** for case
prerequisites and **Current evidence** for working examples that cover
part of a case.

## How to write a case

- Give a live Jido agent a job through its normal interface. Use a deterministic agent so the verdict measures Realm behavior.
- Keep the job and the pass conditions the same across provider variants. The expected cases come from the binding matrix below. Fail a configured case if the provider reports a required capability as absent or unknown. Record separately when a live lane did not run.
- Let the fixture supply approved bindings, inputs, and independent observers. Use the production Realm path for any allocation, execution, policy, or cleanup the case aims to prove.
- Verify the agent's result and the actual effects. Observe the files, resource identity, process, or route before fixture cleanup. Include a failure path where it changes the outcome.
- Keep provider and toolchain names in the binding. Use named Realms in the agent. Treat live remote resources and public ingress as explicit integration variants.

## Required binding cases

Every writable binding starts with the file job, open and close, file
grants, and path confinement (00.01, 00.03, 02.01, 02.02). Use controlled
fixtures for close during work and lost replies (00.04). Bindings with
execution also require capability admission, the program loop, and real
file confinement (02.03, 03.01, 04.01). Each row adds obligations for the
first binding we intend to support.

| Backend | Execution | Additional required cases |
| --- | --- | --- |
| Local | Files only | Independent names and copy with Memory (00.02, 01.03). Borrowed and disposable placement (00.03). |
| Memory | Files only | Independent names and copy with Local (00.02, 01.03). A fresh store per opened instance (00.03). |
| Docker | Bash, Python, JavaScript | Stop, network and resource checks, and setup (03.05, 04.02, 04.04, 04.05). |
| Apple Container | Bash | Same initial cases as Docker (03.05, 04.02, 04.04, 04.05). |
| Sprites | Bash | Attach and fresh allocation, private preview, copy from Local, and retained reopen (03.05, 05.01, 06.04, 07.01, 08.01). |
| S3 | Files only | Scoped prefix, exact bytes, and conditional changes (01.07). |
| GitHub | Files only | Approved branch writes, conflicts, and a pinned read-only view (01.08). |

Run the Docker, Apple Container, and Sprite lanes on real resources.
Record the cases that ran (06.03). Run the coding job (08.02) on every
binding that offers the required toolchain and a writable execution tree.
Run the HTML artifact case (08.03) on Local and Memory with a host
presenter, and on coding bindings that offer artifact presentation.
Run the private preview, startup failure, and cross-Realm preview
(05.01, 05.02, 08.01) on every binding that offers private ingress.
Run the secret checks (04.03) for bindings that supply secrets to code.
Public ingress (05.03) is a separate lane with explicit host configuration.

| Additional execution binding | Required cases beyond the common execution checks |
| --- | --- |
| Memory or Local with mediated Lua | Resource limits and staged output on a file revision (03.03, 04.04). |
| Memory with a Wasm runtime | Build and run an agent-authored artifact. Verify compiler and guest grants and declared host capabilities (03.02, 04.01, 04.04). |
| Managed host over SSH | Optional remote binding. Verify target identity on open and reconnect, one scoped remote tree, unknown run outcomes, and independent remote stop confirmation where claimed (06.05). Repeat stale writer checks if the provider grants external maintenance access (07.05). |

Listing, search, streaming, snapshots, and background or interactive
runs each have separate cases. Include those cases when the target
binding commits to the capability. Use 03.07 for host-approved commands
on file or execution bindings and 04.07 for read-only input mounts where
offered. Use chapter 05 for service ingress, including an ingress adapter
that uses an SSH tunnel. Use
[the vision](../../VISION.md#extension-surfaces) to distinguish storage,
placement, execution, and ingress.
