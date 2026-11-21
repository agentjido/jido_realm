# 05.02 Handle a service start failure

## Agent job

Start an application that exits before it responds or never reaches readiness. Ask the agent to inspect the failure and start a corrected version.

## Fixture and variants

Control health and time in a service-capable fixture. Observe the listener and routes independently.

## Pass conditions

- The initial run returns diagnostics and never reports a ready URL. Cleanup removes its listener and route. The corrected version reaches readiness and responds.

## Build on

[05.01 Start a private preview](../05_01_start_a_private_preview/README.md)

## Current evidence

[Docker startup failure and timeout tests](../private_preview_test.exs)

[Chapter index](../README.md)
