# 08.02 Build, test, and hand off

## Agent job

Give a coding agent a small repository with a failing test. Ask it to
inspect the project, prepare its toolchain, reproduce the failure, fix
the source, and run the build and tests again. The build produces an HTML
report. Ask the agent to return the reviewable diff, test results, and
report tied to the source it tested.

## Fixture and variants

Start with a small fixture repository and a deterministic agent. The
host supplies the same base revision and an approved toolchain with
dependencies available. The job runs on Docker first, then Apple
Container and Sprites. A new provider runs the same job and checks if it
supplies the required capabilities. Let the fixture supply the binding
and direct observers. The agent drives file, build, test, and close
operations through Realm.

For the retained variant, give the coding agent write access. Then give
a second agent read-only access to the retained result. Change the live
source after the test passes and before the reviewer opens the result.

## Pass conditions

- The first test run returns the expected failure and diagnostics. The
  agent can edit the code through Realm and build and test that edit.
  The runner's output is available through the Realm file surface at the
  publication point the Profile specifies.
- An independent observer checks that the diff matches the requested
  change, the second run passes, and the HTML output contains the
  expected result. A failed test blocks handoff as ready.
- The handoff identifies the base revision and the exact tested source,
  diff, output, and run results. The retained reviewer can verify the
  tested revision after the live source changes and cannot edit it.
- In the [artifact variant](../08_03_publish_and_show_an_html_artifact/README.md),
  the reviewer opens the tested report from the agent's result.

## Build on

[02.01 Authorize by operation](../../02_policy_and_admission/02_01_authorize_by_operation/README.md) · [03.02 Build and test with a toolchain](../../03_program_execution/03_02_build_and_test_with_a_toolchain/README.md) · [04.05 Prepare an environment](../../04_sandbox_and_setup/04_05_prepare_an_environment/README.md). The retained variant also uses [07.01 Reopen work with another agent](../../07_retention_and_recovery/07_01_reopen_work_with_another_agent/README.md).

## Current evidence

The repair action runs with Lua on Local and Memory and with Python on
Docker. It reads and edits source through Realm, runs the failed and fixed
verification, and saves the HTML produced on stdout. The Docker runs use
read-only staged inputs. A second failed verification leaves the edited
source available for inspection and returns no ready artifact. Apple
Container, Sprites, and the full retained handoff are later variants.

```sh
mix test test/integration/08_composed_jobs/08_02_build_test_and_hand_off
JIDO_REALM_DOCKER_CONTEXT=orbstack mix test test/integration/08_composed_jobs/08_02_build_test_and_hand_off --only docker
```

[Chapter index](../README.md)
