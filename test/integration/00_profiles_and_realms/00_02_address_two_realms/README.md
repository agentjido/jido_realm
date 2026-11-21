# 00.02 Address two Realms

## Agent job

Give one agent two named Realms. Ask it to save different notes at the same relative path in each place.

## Fixture and variants

Bind `:source` to Local and `:target` to Memory. Open two fresh instances of one Profile as a second case.

## Pass conditions

- Each observer reads its own note. An undeclared Realm name fails before any file changes.
- If the host omits a binding for a declared Realm, the agent cannot open either placement.

## Build on

[00.01 Organize a note](../00_01_organize_a_note/README.md)

## Current evidence

[Existing file test](../../../jido/named_realms_test.exs)

[Chapter index](../README.md)
