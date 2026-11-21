# 01.04 Move without losing the source

## Agent job

Ask the agent to move a file between Realms. Repeat while the destination copy fails or the source changes before deletion.

## Fixture and variants

Use two file Realms and a controlled fault at the copy or delete boundary. Observe both stores after each attempt.

## Pass conditions

- Success leaves the verified destination and conditionally removes the source at the copied revision. A failed or unconfirmed copy preserves the source. If the source changes, report the incomplete move and preserve the newer bytes.

## Build on

[01.02 Edit against a revision](../01_02_edit_against_a_revision/README.md) · [01.03 Copy between Realms](../01_03_copy_between_realms/README.md)

[Chapter index](../README.md)
