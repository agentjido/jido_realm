# 00.04 Close during work

## Agent job

Start a write, close the session while the write is in progress, and try another write. Then retry close after losing its reply.

## Fixture and variants

Hold an admitted write at a controlled point. Observe the session, file result, and resource release. Use a borrowed placement and a disposable one. Repeat with an execution binding that has an active run.

## Pass conditions

- When close begins, new work on that session is denied before provider dispatch. The admitted work finishes or stops under the close policy. A confirmed close leaves no writer on that session.
- A lost release reply leaves close unconfirmed. Once the provider can report release, a retry confirms the same close without releasing twice. The borrowed resource survives and the disposable one is removed under its policy.
- If the lease owner exits during a write, the session denies new work. A write that took effect and lost its reply reports an unknown outcome. The provider releases the lease after the worker exits and the observer sees a single write attempt.
- After a normal session shutdown, the old handle denies new work. The observer checks the owned or borrowed resource before fixture cleanup.

## Build on

[00.03 Open and close a Realm](../00_03_open_and_close_a_realm/README.md)

[Chapter index](../README.md)
