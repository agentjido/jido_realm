# 01.01 Edit and list a tree

## Agent job

Ask the agent to organize a small project. It creates a directory, adds and edits notes, lists the directory, renames a draft, and removes a finished note.

## Fixture and variants

Use the same tree and assertions on Local and Memory. Repeat on each provider that offers the directory contract.

## Pass conditions

- Listing reports the expected entries and paths relative to the Realm root. File bytes match the final edits. A rename to an occupied path preserves both entries.
- On bindings that require explicit parent directories, create under a missing parent fails. The same request can succeed after the agent creates the parent.

## Build on

[00.01 Organize a note](../../00_profiles_and_realms/00_01_organize_a_note/README.md)

## Current evidence

The existing suite checks file edits and parent paths. Listing and rename still need tests. [Current file tests](../../../jido/file_conformance_test.exs)

[Chapter index](../README.md)
