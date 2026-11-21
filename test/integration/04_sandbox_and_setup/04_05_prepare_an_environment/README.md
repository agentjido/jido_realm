# 04.05 Prepare an environment

## Agent job

Ask the agent to write and run a setup script, then use the file or tool it prepares in a later run. Repeat with a setup script that fails.

## Fixture and variants

Use an isolated profile with explicit file and network grants. Seed a harmless protected file outside the permitted tree.

## Pass conditions

- Successful setup makes the expected result visible to the program. Setup stays within its grants. Failed setup never marks the environment ready or saves reusable prepared state.

## Build on

[03.01 Write, run, and revise a program](../../03_program_execution/03_01_write_run_and_revise/README.md) · [04.01 Confine code to approved files](../04_01_confine_code_to_approved_files/README.md) · [04.02 Control network access](../04_02_control_network_access/README.md)

## Current evidence

[Lua setup on Local and Memory](../mediated_build_test.exs)

[Runnable reference](../../../../examples/realm/04_prepare_and_preview_an_app/README.md)

[Chapter index](../README.md)
