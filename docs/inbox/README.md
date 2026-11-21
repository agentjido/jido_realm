# Documentation inbox

Review each item against current code, tests, or an accepted decision before
moving it into the main documentation. Keep the original path in this log.

| Date | Source | Destination | Status |
| --- | --- | --- | --- |
| 2026-11-19 | `docs/atomic-workspaces.md` | [Owned atomic workspaces](docs/atomic-workspaces.md) | New. Review current API claims and retain the original history. |
| 2026-11-19 | Owner's infrastructure design review | [Persistent infrastructure and writer ownership](../decisions/2026-11-19-persistent-infrastructure.md) | Placed. Accepted design boundary. |
| 2026-11-21 | Shell guide | [Jido Shell](https://github.com/agentjido/jido_shell) | Maintained by the standalone package. |
| 2026-11-21 | VFS guide | [Jido VFS](https://github.com/agentjido/jido_vfs) | Maintained by the standalone package. |

## Paths kept in place

- Root README, contribution guide, usage rules, change log, and agent
  instructions are entry points or package files. The root API specification,
  Sandbox, and Deploy guides also ship in the package.
- `docs/source-imports.md` and `docs/workspace-asset-lifecycle.md` are package
  or ExDoc inputs.
- `docs/plans/` is the plan directory. Superseded merge plans are archived
  outside the active checkout.
- `bench/search/` contains reports kept with the benchmark material.
