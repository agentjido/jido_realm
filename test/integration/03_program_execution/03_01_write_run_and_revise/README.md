# 03.01 Write, run, and revise a program

## Agent job

Give the agent sample data. Ask it to write an entry point, a helper, and an input file into the Realm. It runs the program, fixes an error in the helper, and runs it again.

## Fixture and variants

Run mediated Lua on Memory and Local. Run Bash, Python, and JavaScript
in Docker with read-only inputs. Use the same input and expected report
with source files for each language. Future variants include Apple
Container, Sprites, and a Wasm runtime.

## Pass conditions

- The agent writes all three files and starts the program through Realm. The entry point loads the helper and reads the input. The agent can read the report at the binding's declared visibility point.
- The failed run returns a distinct failure result with bounded diagnostics. After the agent repairs the source, the next run returns success and produces the expected changed output. The fixture reads the report independently.

## Build on

[02.03 Require a verified capability](../../02_policy_and_admission/02_03_require_a_verified_capability/README.md)

## Current evidence

The agent uses `realm.program.run` for all four runtimes. Lua publishes the
report through its staged file bridge. The Docker variants save the returned
report through the Realm file API. [Program case](program_test.exs) ·
[Lua report example](../../../../examples/realm/03_build_and_revise_a_report/README.md)

[Chapter index](../README.md)
