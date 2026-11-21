# 02.03 Require a verified capability

## Agent job

Ask the agent to open a Profile that requires a specific runtime control. Try confirmed, unsupported, and unknown provider responses.

## Fixture and variants

Use a recording provider with configurable capability results. Repeat the supported case on a real runtime when available.

## Pass conditions

- Only the confirmed case becomes ready. Optional capabilities appear only when the provider supports them and the host grants them. Failed open releases any test-owned allocation and preserves borrowed resources.

## Build on

[00.03 Open and close a Realm](../../00_profiles_and_realms/00_03_open_and_close_a_realm/README.md)

[Chapter index](../README.md)
