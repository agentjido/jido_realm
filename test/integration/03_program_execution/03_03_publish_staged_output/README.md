# 03.03 Publish staged output

## Agent job

Ask a program to write a report and its summary on a staged tree. Repeat with a program failure, a newer edit in the source tree, and an interrupted publication.

## Fixture and variants

Use a staged execution profile, such as mediated Lua, with previous outputs and a controlled concurrent edit. The initial contract publishes per file. If a binding claims atomic publication of the whole change set, verify that claim separately.

## Pass conditions

- The run reads its own staged writes. Other readers see the prior files until publication. On success, the agent and observer both see the new outputs.
- A failed run preserves both prior outputs. A stale publication reports a conflict and preserves the newer edit.
- Interrupt publication between output files. A per-file binding reports which files it published and any result it cannot confirm. An atomic binding leaves either the complete prior set or the complete new set.

## Build on

[01.02 Edit against a revision](../../01_files_and_transfer/01_02_edit_against_a_revision/README.md) · [03.01 Write, run, and revise a program](../03_01_write_run_and_revise/README.md)

## Current evidence

The Lua adapter stages writes during evaluation and publishes them one at
a time. The cases observe a concurrent edit and a lost publication reply.
[Publication cases](publication_test.exs) ·
[Lua example](../../../../examples/realm/03_build_and_revise_a_report/README.md)

[Chapter index](../README.md)
