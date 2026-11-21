# Jido Realm examples

Jido Realm gives an agent a place to work. Start with a job the agent can
complete, then check the result from outside the agent. Keep the job and
its assertions the same when a different provider can meet the contract.

```sh
mix test.realm --trace
```

This command runs the Realm examples and the Realm integration ladder.
Add `--include docker --include apple_container --include browser` for
the local runtime cases. Set up the fixtures first. Create the Docker
preview network with `docker network create jido-realm-coding-preview-local`
if it does not exist.
[Realm prerequisites](../../README.md#check-host-and-test-prerequisites)

| Example | What it proves today | Runs on |
| --- | --- | --- |
| [01 Organize a note](01_organize_a_note/README.md) | A Jido agent declares one Realm and moves a draft into its final file. | Local, Memory |
| [02 Copy between Realms](02_copy_between_realms/README.md) | One agent copies a note between two declared Realms. An occupied destination keeps its previous content. | Local → Memory, Memory → Local |
| [03 Build and revise a report](03_build_and_revise_a_report/README.md) | A Jido agent runs Lua files through Realm, checks the file boundary, and preserves the last successful report when a run fails. | Local + Lua, Memory + Lua |
| [04 Prepare and preview an app](04_prepare_and_preview_an_app/README.md) | A test runner starts an offline setup container and a separate app container. A loopback preview serves the setup output and closes on stop. | Apple Container |
| [11 Work on a shared checkout](11_work_on_a_shared_checkout/README.md) | An agent edits a checkout, runs a check, and saves the tree. A read-only agent opens that revision in a fresh BEAM. | Docker |

The integration ladder also has a [Node report agent](../../test/integration/04_sandbox_and_setup/04_01_confine_code_to_approved_files/README.md).
It accepts one job signal and uses `Realm.exec` to run the program in Docker.

The [coding agent workbench](10_coding_agent_workbench/README.md) runs as a
separate Phoenix app. It uses a local model to build and preview Phoenix and
TypeScript projects on Local, Docker, Apple Container, and Sprites.

## Use the examples to rebuild Realm

1. **Keep 01 and 02 green.** They exercise the agent DSL, host bindings,
   and the shared file interface. Use the file contracts for path checks,
   file errors, and backend isolation. [File contracts](../../test/jido/file_conformance_test.exs)
2. **Run the program in 03.**
   The agent writes setup and program files, runs them through Realm, gets
   diagnostics from a failed run, edits the program, and reruns it.
   The observer checks the report and the protected file.
3. **Give the agent the service lifecycle in 04.** The agent starts the
   service on an assigned port. An independent HTTP client verifies the
   response after readiness and verifies that the route closes on stop.
4. **Combine 02 and 04 on a remote provider.** Run the same copy job with
   a Local source and a Sprite target. Start the server in the target and
   verify that it serves the exact copied bytes. Add separate cases for
   reopening the same Realm and for a host-granted public route.

The fixture supplies approved bindings and observers. Put provider
allocation, policy checks, and cleanup that Realm promises in the production
path so that examples can verify them. The
[conformance map](../../docs/conformance-map.md) describes those contracts.
