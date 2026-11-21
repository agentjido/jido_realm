# 04.01 Confine code to approved files

## Agent job

Send one report request to a live Jido agent. The agent opens its Realm,
writes a Node program and its inputs, calls `Realm.exec`, closes the
Realm, and returns the result.

## Fixture and variants

Use a Local tree with a real Docker runner. The fixture supplies the
approved image and creates a harmless file outside the Realm. Use the
same job to check that open fails with files alone or with a runner that
lacks the Profile's required controls.

## Pass conditions

- Node reads the approved input, writes a report in scratch space, and
  returns the exact report it reads back.
- Node cannot read an undeclared Realm file or the host file. It cannot
  change the read-only input. The process runs as a non-root user and
  sees only the loopback network interface.
- The fixture reads the original files directly, checks that the scratch
  report stayed out of the Realm tree, and checks that Docker removed
  the run's container.

Run the case with a cached Node image and a Docker context that can mount
local paths.

```sh
mix test test/integration/04_sandbox_and_setup/04_01_confine_code_to_approved_files --include docker
```

The same file contract can drive Apple Container, a Sprite, or a Wasm
runner when each has a Realm binding. Each binding must supply its own
evidence for the controls it claims.

## Build on

[02.02 Confine file paths](../../02_policy_and_admission/02_02_confine_file_paths/README.md) · [03.01 Write, run, and revise a program](../../03_program_execution/03_01_write_run_and_revise/README.md)

## Current evidence

[Node report agent and test](node_report_test.exs) · [Lua file access checks](../../../../examples/realm/03_build_and_revise_a_report/README.md) · [Apple Container setup checks](../../../../examples/realm/04_prepare_and_preview_an_app/README.md)

[Chapter index](../README.md)
