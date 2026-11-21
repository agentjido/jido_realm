# 06.03 Repeat on live sandboxes

## Agent job

Exercise a lane through the live provider. Open a Realm, write and run a Bash program against its tree, then close through Realm. Record the concrete cases that ran for the binding.

## Fixture and variants

Start with Docker and Apple Container. Add the Sprite binding when it is available. Use the test inputs, ownership policy, and observers for each binding in the [required case matrix](../../README.md#required-binding-cases).

## Pass conditions

- Every configured binding runs the applicable cases in the matrix. An absent or unknown required capability fails the lane. A lane that does not run has no conformance result.
- Direct observers confirm the resource identity, expected file results, required controls, and cleanup before the fixture removes test-owned resources. Record the binding and the case IDs that ran.

## Build on

[03.01 Write, run, and revise a program](../../03_program_execution/03_01_write_run_and_revise/README.md) · [04.01 Confine code to approved files](../../04_sandbox_and_setup/04_01_confine_code_to_approved_files/README.md) · [06.01 Add a provider](../06_01_add_a_provider/README.md)

## Current evidence

The Apple Container harness runs `/bin/sh` and checks setup with a loopback preview. The live Realm lane must run Bash through Realm. [Apple Container example](../../../../examples/realm/04_prepare_and_preview_an_app/README.md)

[Chapter index](../README.md)
