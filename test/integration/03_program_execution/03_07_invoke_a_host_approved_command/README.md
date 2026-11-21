# 03.07 Invoke a host-approved command

## Agent job

Discover a host-approved report command on an open Realm. Call it with a relative input path and a format. Try again with invalid arguments and from a session without the command grant.

## Fixture and variants

Register a small trusted command that reads one approved file and returns a formatted report. Record dispatch and observable effects. Start with a direct agent call on a file Realm. If the binding exposes the command to an embedded runtime, repeat inside an agent-authored program.

## Pass conditions

- The authorized session discovers the stable name and argument schema. A valid call reads the expected Realm file and returns the expected result.
- Invalid arguments and a missing command grant fail before dispatch. The handler receives only scoped access to the files it needs. Direct calls and calls from an embedded runtime enforce the same command and file grants.
- A command grant applies only to the approved implementation. An agent request cannot change the implementation or expand its authority.

## Build on

[02.01 Authorize by operation](../../02_policy_and_admission/02_01_authorize_by_operation/README.md). The runtime bridge variant also builds on [03.01 Write, run, and revise a program](../03_01_write_run_and_revise/README.md).

## Current evidence

[Local and Memory command tests](command_test.exs)

Shell has a fixed command registry and language-specific bridges. The Realm case adds discovery and grants per session. [Shell command registry](../../../../../jido_shell/lib/jido_shell/command/registry.ex)

[Chapter index](../README.md)
