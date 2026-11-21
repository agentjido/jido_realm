# 04.03 Scope secrets

## Agent job

Give an approved run one synthetic secret and ask a second run to check whether it can see it. Inspect diagnostics and retained output.

## Fixture and variants

Use fixture-only values, one allowed consumer, and an unauthorized run. Give the allowed program a read-only workspace. Observe provider credentials, normal diagnostic records, and retained state without printing secret values.

## Pass conditions

- Only the permitted run receives the fixture secret through the approved channel. Provider credentials stay outside both runs. The injection mechanism leaves no value in the standard diagnostics or retained state. A later run without the grant cannot reuse the injection.

## Build on

[02.01 Authorize by operation](../../02_policy_and_admission/02_01_authorize_by_operation/README.md) · [03.01 Write, run, and revise a program](../../03_program_execution/03_01_write_run_and_revise/README.md)

[Chapter index](../README.md)
