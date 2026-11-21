# 06.02 Recover a lost open reply

## Agent job

Ask the agent to open a Realm, lose the provider reply after an allocation, then retry the same request.

## Fixture and variants

Use a controlled transport that completes an allocation before it drops the reply. Hold reconciliation unavailable, then restore it. Observe resources and leases directly.

## Pass conditions

- While confirmation is unavailable, retry reports an unknown outcome and does not create a second allocation. After confirmation returns, retry resolves the same allocation. An unclaimed or late allocation is released under the agreed ownership policy.

## Build on

[06.01 Add a provider](../06_01_add_a_provider/README.md)

[Chapter index](../README.md)
