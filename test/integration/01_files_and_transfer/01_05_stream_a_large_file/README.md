# 01.05 Stream a large file

## Agent job

Ask the agent to copy a binary artifact larger than the configured transfer buffer, then repeat with an interrupted source.

## Fixture and variants

Use profiles that declare streamed binary I/O. Supply fixed binary bytes, a digest, and a controllable interruption.

## Pass conditions

- The completed destination matches the source digest. An interrupted copy leaves a previous destination intact and reports an incomplete transfer.
- If the destination publishes the file and the source session stops before the reply, the agent gets an unknown result. The observer sees the full file at the destination and a single write attempt.

## Build on

[01.03 Copy between Realms](../01_03_copy_between_realms/README.md)

[Chapter index](../README.md)
