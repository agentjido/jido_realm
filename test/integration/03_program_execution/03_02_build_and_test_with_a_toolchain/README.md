# 03.02 Build and test with a toolchain

## Agent job

Ask the agent to build a program from source, run its tests, and execute the artifact it built.

## Fixture and variants

Supply a pinned toolchain, a known input, and a working directory inside the Realm. Include a native build and a build that produces a Wasm artifact. For the Wasm binding, supply an approved compiler and declare the WASI interface and file grants for the guest.

Include a filename with spaces and punctuation. Use a recording runner for invalid working directories and for stale inputs when the binding supports an input revision check.

## Pass conditions

- The build uses the selected toolchain, literal arguments, and the expected working directory. The run uses the artifact the agent just built and produces the expected report. A missing required toolchain fails before the build.
- An invalid working directory fails before launch. When the agent supplies an expected input revision, a stale revision also fails before launch. A pre-launch check records the admitted revision. A binding that promises fixed inputs must supply a tree that stays fixed during the run.
- A failing test produces a failed result with diagnostics and the agent does not run the untested artifact. After the agent corrects the source, it rebuilds, passes the tests, and runs the new artifact in that order.
- For Wasm, verify the compiler and guest grants separately. The guest can read its approved input and write the report. It cannot see fixtures outside its declared tree.

## Build on

[03.01 Write, run, and revise a program](../03_01_write_run_and_revise/README.md)

## Current evidence

[Docker Python build and binary round trip](toolchain_test.exs)

Workspace tests literal arguments and a working directory and supports a pre-launch file-view check. Its batch example stops at the first failure and keeps the effects of completed steps. The agent can show the same order with individual Realm calls. [Arguments and working directory](../../../../examples/02_commands/02_01_run_argv_and_cwd/README.md) · [File views](../../../../HOST.md#command-file-views) · [Ordered batch](../../../../examples/02_commands/02_03_run_an_ordered_batch/README.md)

[Chapter index](../README.md)
