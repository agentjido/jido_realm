# 03.04 Observe a background run

## Agent job

Ask the agent to start a report job that emits progress and keep working while it runs. Use its run ID to inspect, follow, and wait for it.

## Fixture and variants

Use a profile that supports background execution and streaming. Gate a short program at known progress points so the test can observe it before exit.

## Pass conditions

- Progress is available before the terminal result. Observers can match output and exit status to the same run ID. A slow observer sees the declared retention or gap behavior.

## Build on

[03.01 Write, run, and revise a program](../03_01_write_run_and_revise/README.md)

## Current evidence

[Lua progress on Local and Memory](background_run_test.exs)

[Chapter index](../README.md)
