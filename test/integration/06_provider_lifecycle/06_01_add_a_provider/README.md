# 06.01 Add a provider

## Agent job

Open the same file Profile through a second provider connector and give the agent a known file job. Close through Realm.

## Fixture and variants

Use a controlled transport with an allocation log and a direct store observer. The fixture supplies the transport and settings.

## Pass conditions

- Realm asks the provider to allocate or attach and receives the confirmed resource reference. The standard file job works. Close releases the session and retains or removes the actual resource as promised.

## Build on

[00.03 Open and close a Realm](../../00_profiles_and_realms/00_03_open_and_close_a_realm/README.md) · [02.03 Require a verified capability](../../02_policy_and_admission/02_03_require_a_verified_capability/README.md)

[Chapter index](../README.md)
