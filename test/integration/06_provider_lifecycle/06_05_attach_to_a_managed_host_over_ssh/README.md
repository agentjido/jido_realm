# 06.05 Attach to a managed host over SSH

## Agent job

Open a Realm on an approved existing machine, save a small program, and run it through the SSH binding. Read the output through Realm, then close the session.

## Fixture and variants

Use a controlled SSH host with a known host key and an approved remote directory. Bind a scoped file adapter or staging process to the directory the remote program uses. Include a host identity mismatch at open and after reconnect. Drop the connection after a run starts and before Realm receives its exit status.

## Pass conditions

- Realm verifies the approved host identity before file or execution requests, including after reconnect. Host credentials stay outside the agent and the guest program.
- The remote program reads the input the agent wrote. Realm reads the exact output bytes. Arguments are passed literally and the working directory stays within the bound tree.
- Closure without a terminal result leaves the run outcome unknown. Reconnect does not replay it. A binding that promises recovery resolves the same run ID. A binding that promises confirmed stop verifies independently that remote writers have stopped.
- Close releases the session under its policy and preserves the borrowed machine. A Profile that requires isolation opens only with a remote environment that can enforce it.

## Build on

[03.01 Write, run, and revise a program](../../03_program_execution/03_01_write_run_and_revise/README.md) · [06.01 Add a provider](../06_01_add_a_provider/README.md)

## Current evidence

Shell exercises remote commands and output limits against a test SSH server. Its existing backend accepts host keys by default and can report success when a channel closes without an exit status. Verify both behaviors at the Realm boundary before using this backend in a binding. [Shell SSH tests](../../../../../jido_shell/test/jido/shell/backend/ssh_test.exs) · [Shell SSH backend](../../../../../jido_shell/lib/jido_shell/backend/ssh.ex)

[Chapter index](../README.md)
