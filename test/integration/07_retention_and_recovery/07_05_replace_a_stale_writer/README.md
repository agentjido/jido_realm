# 07.05 Replace a stale writer

## Agent job

Lose contact with an agent that has an active writer. Try to reopen the Realm for another writer before and after the old lease is revoked and its process stops.

## Fixture and variants

Use a retained provider with an independently observed writer. Simulate a lost connection and a delayed stop confirmation.
For a binding that offers an exclusive maintenance handoff, repeat with
an external writer such as an approved SSH session.

## Pass conditions

- Realm blocks replacement until the old lease cannot start work and existing writers have stopped. The replacement can write after confirmation. Old sessions cannot write, start a run, or save through their stale handles.
- In the maintenance variant, Realm blocks a new writer and any save that requires exclusive access while the external writer can still change the tree. The provider confirms that the external lease ended and its writers stopped before Realm grants write access again.

## Build on

[07.04 Recover a run after controller loss](../07_04_recover_a_run_after_controller_loss/README.md)

## Current evidence

Workspace exercises the lease and writer checks with a controlled maintenance console. [Maintenance handoff](../../../../examples/06_providers_and_persistent_infrastructure/06_05_hand_off_to_an_external_maintainer/README.md)

[Chapter index](../README.md)
