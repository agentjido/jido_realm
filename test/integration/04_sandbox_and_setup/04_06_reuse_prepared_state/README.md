# 04.06 Reuse prepared state

## Agent job

Open two Realms with the same approved setup inputs. Open another after a change to the recipe, toolchain, input, or required policy.

## Fixture and variants

Use a provider with a prepared-state cache. Observe recipe executions and use a known prepared file to verify the result.

## Pass conditions

- A matching Realm reuses the prepared state. A changed input runs setup before readiness. Failed or superseded setup is excluded from later reuse.

## Build on

[04.05 Prepare an environment](../04_05_prepare_an_environment/README.md)

[Chapter index](../README.md)
