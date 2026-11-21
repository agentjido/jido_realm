# 07.02 Save and restore a snapshot

## Agent job

Ask the agent to save completed work, change the live tree, and close its disposable Realm. Restore the saved work to a new placement from a fresh process.

## Fixture and variants

Use a Profile that declares snapshots. Start with a file snapshot. Repeat across providers when they promise portable restores.

## Pass conditions

- The fixture confirms that the first placement is gone. Restore still returns the saved bytes and supported metadata from the selected snapshot. A failed later save leaves the previous snapshot usable.

## Build on

[00.03 Open and close a Realm](../../00_profiles_and_realms/00_03_open_and_close_a_realm/README.md)

[Chapter index](../README.md)
