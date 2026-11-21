# 07.01 Reopen work with another agent

## Agent job

Give agent A a durable Realm. Ask it to write source, setup, and outputs, then close its session. Give agent B access to the same Realm.

## Fixture and variants

Start with a retained Local directory. Repeat with a durable Sprite binding. Observe the Realm identity, placement, and bytes.

## Pass conditions

- Agent B reopens the same identity and placement and reads the expected files. The prior session cannot change the Realm. Running processes and routes follow their own stated lifetimes.

## Build on

[00.03 Open and close a Realm](../../00_profiles_and_realms/00_03_open_and_close_a_realm/README.md)

[Chapter index](../README.md)
