# 02.02 Confine file paths

## Agent job

Give the agent an allowed note and a harmless host-only sentinel. Ask it to use relative paths, then verify the boundary rejects paths outside the tree.

## Fixture and variants

Check canonical relative paths on each backend. Select linked-path checks for filesystem bindings and outside-scope sentinels for object and repository bindings.

## Pass conditions

- Allowed reads and writes succeed. Outside paths and disallowed links are rejected. The protected file stays intact. Signal payloads cannot supply host binding options.

## Build on

[00.01 Organize a note](../../00_profiles_and_realms/00_01_organize_a_note/README.md)

## Current evidence

[Existing file test](../../../jido/realm_test.exs)

[Chapter index](../README.md)
