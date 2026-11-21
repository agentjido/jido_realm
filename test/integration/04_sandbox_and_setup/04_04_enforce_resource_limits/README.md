# 04.04 Enforce resource limits

## Agent job

Ask the agent to run a bounded job, then exercise a job that reaches one configured resource ceiling.

## Fixture and variants

Use providers that declare memory, CPU, elapsed time, or output controls. Exercise each promised limit with a safe, small ceiling.

## Pass conditions

- The observer verifies the actual enforced setting or limit outcome. The agent gets bounded diagnostics and can inspect the terminal status. The run follows the stop contract.

## Build on

[02.03 Require a verified capability](../../02_policy_and_admission/02_03_require_a_verified_capability/README.md) · [03.05 Stop a run](../../03_program_execution/03_05_stop_a_run/README.md)

[Chapter index](../README.md)
