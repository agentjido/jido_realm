# 04.02 Control network access

## Agent job

Run the same benign network check with an allowed test endpoint and with outbound access disabled.

## Fixture and variants

Use a controlled endpoint reachable in the allowed case. Observe requests at that endpoint. Use a real provider that declares the network control.

## Pass conditions

- The permitted run reaches the test endpoint. The restricted run reports the denial or connection failure and produces no observed request. A service's inbound route follows its own grant.

## Build on

[02.03 Require a verified capability](../../02_policy_and_admission/02_03_require_a_verified_capability/README.md) · [03.01 Write, run, and revise a program](../../03_program_execution/03_01_write_run_and_revise/README.md)

## Current evidence

[Docker private network test](network_access_test.exs)

[Chapter index](../README.md)
