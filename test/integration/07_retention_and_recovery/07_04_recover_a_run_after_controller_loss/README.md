# 07.04 Recover a run after controller loss

## Agent job

Start a long-running job on a retained provider. Lose the launch reply and the controller. Retry the launch request, then use its run reference to inspect or wait from a new process.

## Fixture and variants

Use a durable runner with a controlled disconnect and an independent process observer. Record the launch request before dispatch. Restore provider reachability after testing the unavailable state.

## Pass conditions

- An unavailable provider leaves the outcome unknown and blocks another writer. When the provider can confirm the run, recovery returns the original run reference and its observed state. The observer counts exactly one launch. An authorized caller can stop that run.

## Build on

[03.04 Observe a background run](../../03_program_execution/03_04_observe_a_background_run/README.md) · [03.05 Stop a run](../../03_program_execution/03_05_stop_a_run/README.md) · [07.01 Reopen work with another agent](../07_01_reopen_work_with_another_agent/README.md)

[Chapter index](../README.md)
