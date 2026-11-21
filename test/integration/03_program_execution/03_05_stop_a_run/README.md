# 03.05 Stop a run

## Agent job

Ask the agent to start a program that writes progress, then cancel it. Repeat with a deadline that expires.

## Fixture and variants

Use an isolated runtime with a controlled writer and, where supported, a child process. Observe the run and file changes directly.

## Pass conditions

- Realm distinguishes cancellation from timeout. Once it confirms stop, the program and its children cannot write. A provider that cannot confirm stop leaves the outcome unknown and blocks an unsafe replacement writer.

## Build on

[03.01 Write, run, and revise a program](../03_01_write_run_and_revise/README.md)

## Current evidence

The cases check a Lua deadline and the disposition of its staged writes,
Docker removal after timeout or excess output, and admission when a
provider cannot confirm stop. Explicit cancellation is a separate part of
this case. [Stop cases](stop_run_test.exs)

[Chapter index](../README.md)
