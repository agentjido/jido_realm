# 05.01 Start a private preview

## Agent job

Ask the agent to start its application on an assigned port and return a private preview link when the application responds.

## Fixture and variants

Start with a local container, then run the same case on Sprites. Use the binding's private access mechanism. Give the authorized and unauthorized clients network reachability to the route. A loopback smoke test only verifies a local reachability boundary.

## Pass conditions

- The link serves the expected bytes after readiness. An unauthorized client cannot open it or reach the guest service through a separate exposed port. Stopping the service ends access through the link and closes the listener.

## Build on

[03.01 Write, run, and revise a program](../../03_program_execution/03_01_write_run_and_revise/README.md) · [03.05 Stop a run](../../03_program_execution/03_05_stop_a_run/README.md)

## Current evidence

[Docker readiness and private access tests](../private_preview_test.exs) ·
[Native service and process-group cleanup tests](../native_preview_test.exs)

The harness runs a shell in Apple Container and checks readiness and stop through loopback. [Apple Container preview](../../../../examples/realm/04_prepare_and_preview_an_app/README.md)

[Chapter index](../README.md)
