# Jido Realm

`jido_realm` contains the Realm agent API and host controls. Shell and VFS
run as separate dependency applications. Use their public APIs.

- `Jido.Realm.Host` manages workspaces, access policy, mounted files, and Shell sessions.
- `Jido.VFS` provides storage adapters and atomic InMemory captures.
- `Jido.Shell` runs commands over mounted filesystems.
- `Jido.Realm.Host.Sandbox` manages execution environments and services.
- `Jido.Realm.Host.Deploy` manages deployment plans and transitions.
- `Jido.Realm` grants agents scoped access to files, commands, and previews.

Use `Jido.Realm.Host.open/1` and `close/1` to manage a live workspace. Use
`capture/1` and revision-checked `replace/3` to work with captured content.
See the [host guide](HOST.md) for the file and execution APIs.

## Checks

- `mix test` runs the default suites.
- `mix test.realm` runs the Realm examples and integration tests.
- `mix test.integration` runs the isolated host examples.
- `mix quality` runs format, compile, lint, type, and documentation checks.
- `mix test.coverage` combines coverage from the default suites and host examples.
- `mix hex.build` is a release check for the Hex dependency graph.

## Scope

The host sets provider orchestration, runtime policy, and Sprite bindings.
Keep host deployment authority separate from Realm agent grants.

See [imported source revisions](docs/source-imports.md) for provenance.
Do not edit `CHANGELOG.md`. The release workflow generates it from Git history.
