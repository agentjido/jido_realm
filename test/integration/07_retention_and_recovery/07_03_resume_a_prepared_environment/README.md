# 07.03 Resume a prepared environment

## Agent job

Close a prepared environment and reopen it later. Ask the agent to use the prepared files after the resume hook runs.

## Fixture and variants

Use a retained provider that declares a resume hook. Observe setup and resume executions separately.

## Pass conditions

- A matching prepared environment survives as declared. Resume runs under its current grants before use. An invalid prepared result requires fresh setup.

## Build on

[04.06 Reuse prepared state](../../04_sandbox_and_setup/04_06_reuse_prepared_state/README.md) · [07.01 Reopen work with another agent](../07_01_reopen_work_with_another_agent/README.md)

[Chapter index](../README.md)
