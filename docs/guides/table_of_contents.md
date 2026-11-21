# Realm guides

Use this index to find Realm workflows, supporting APIs, and runnable
examples. Reviewed on 2026-11-19.

## Start here

- [Install from a local checkout](../../HOST.md#use-from-another-project)
- [Open one working tree](../../HOST.md#open-one-working-tree) to edit files,
  run a command, save the result, and reopen it for review.
- [Run the numbered examples](https://github.com/agentjido/jido_realm/tree/main/examples)
  for workflows that exercise the public API.

## Work with files and commands

- `Jido.Realm.Host` covers relative paths, revision-checked edits, file search,
  and large file reads and writes.
- Use `Jido.Realm.Host.run/3` for literal arguments and a working directory.
  Use `Jido.Realm.Host.batch/2` for ordered edits and commands.
- Use `Jido.Realm.Host.info/1` and `Jido.Realm.Host.output/3` to inspect a live
  command. Use `Jido.Realm.Host.cancel/2` to request a stop.

## Choose an execution environment

- `Jido.Realm.Host.Profile` defines the provider, tools, limits, and required
  capabilities. `Jido.Realm.Host.Policy` defines the operations it grants.
- [Sandbox guide](../../SANDBOX.md) covers local processes, containers,
  service lifetimes, and cleanup. Check the provider's capabilities before
  you depend on an isolation or cancellation guarantee.
- `Jido.Realm.Host.Provider` defines the callbacks for hosts that supply their
  own file tree and runner or attach to persistent infrastructure.

## Save, recover, and deploy

- Use `Jido.Realm.Host.save/1` for a portable tree. Keep its
  `Jido.Realm.Host.Snapshot` reference to [reopen it for review](../../HOST.md#open-one-working-tree).
- Use `Jido.Realm.Host.InfrastructureRef` to identify a persistent resource.
  Use `Jido.Realm.Host.CommandRef` and `Jido.Realm.Host.recover_command/4` to
  inspect, wait for, or stop a job after client loss. The host confirms old
  writers have stopped before it grants replacement write access.
- [Deploy guide](../../DEPLOY.md) covers [saved trees](../../DEPLOY.md#saved-workspace-trees),
  [recovery](../../DEPLOY.md#failure-and-recovery), and
  [OTP release upgrades](../../DEPLOY.md#otp-release-upgrade).

## Use Shell and VFS directly

- [Shell sessions](https://github.com/agentjido/jido_shell) covers Shell commands, mounts, and backends.
- [Virtual filesystems](https://github.com/agentjido/jido_vfs) covers storage adapters, streaming,
  versioning, and atomic memory captures.
- [VFS in Jido agents](https://github.com/agentjido/jido_vfs/blob/main/docs/jido-agent-integration.md) describes how a host
  application can expose selected operations as Actions.

## Maintain the package

- [VFS adapter checklist](https://github.com/agentjido/jido_vfs/blob/main/docs/adapter-onboarding-checklist.md)
- [Shell guardrails](https://github.com/agentjido/jido_shell/blob/main/GUARDRAILS.md) and [migration](https://github.com/agentjido/jido_shell/blob/main/MIGRATION.md)
- [Contributing](../../CONTRIBUTING.md), [change log](../../CHANGELOG.md), and
  [source imports](../source-imports.md)
- [License](../../LICENSE)

## Earlier designs

- [Realm API proposal](../../API_SPEC.md)
- [Realm asset lifecycle proposal](../workspace-asset-lifecycle.md)
