# 00.01 Organize a note

## Agent job

Give an agent one job to create a draft, read it back, write the final note, and remove the draft after the final write succeeds.

## Fixture and variants

Bind the agent's `:work` Realm to Local, then run the same job and checks on Memory and each writable binding. Use UTF-8 fixtures at the root. Include a seeded file under a read-only grant.

## Pass conditions

- The agent returns the final path. A direct store reader verifies the exact contents and confirms that the draft is gone.
- A duplicate create reports a conflict and preserves the original bytes. Read, edit, and delete report a missing file at an absent path. Under the read-only grant, read succeeds and all mutations are denied.

## Current evidence

[Runnable reference](../../../../examples/realm/01_organize_a_note/README.md)

[Chapter index](../README.md)
