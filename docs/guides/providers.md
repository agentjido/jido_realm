# Providers

The host selects a provider when it starts a managed session. The provider
reports the capabilities of the placement it opens. The session prepares
the selected runners and preview adapter. Open returns the capabilities
that the Profile requests, the host permits, and the session can supply.
If a required capability is unavailable, open returns
`{:error, {:required_capability_unavailable, capability}}`. The binding's
grants control which operations the agent can call.

## Select file storage

| Placement | Session provider | File access | Close |
| --- | --- | --- | --- |
| Memory | `{Jido.Realm.Placement, :memory}` | Text, tree, revisions, search, streams | Stops the owned store. |
| Local | `{Jido.Realm.Placement, {:local, root}}` | Text, tree, revisions, search, streams | Deletes the owned directory. |
| VFS | `{Jido.Realm.Provider.VFS, filesystem}` | Text create, read, edit, and delete | Preserves the host store. |
| Sprite | `{Jido.Realm.Provider.Sprite, options}` | Reads approved UTF-8 files | Preserves borrowed Sprites and deletes owned Sprites. |
| Realm Docker | `{Jido.Realm.Provider.SharedCheckout, options}` | Text, tree, and revisions on the command mount | Preserves the host checkout and deletes owned scratch storage. |

For an owned Local Realm, supply a new directory path with an existing
parent. To borrow an existing Local directory or Memory store, use
`{Jido.Realm.Placement, {:borrow, binding}}`. Use `{Jido.Realm.Local, root}`
for a Local directory or `{Jido.Realm.Memory, store}` for a Memory store.
Close preserves a borrowed placement. Keep other writers from changing
directories or links during a Local operation.

For VFS, start a filesystem adapter that supports `capture/1` and
`apply_edits/3`. For example, use the Memory adapter in the VFS version
that Realm pins.

```elixir
alias Jido.Realm.{Provider, Session}
alias Jido.VFS.Adapter.InMemory

filesystem = InMemory.configure(name: :realm_guide_files)
{:ok, _store} = InMemory.start_link(filesystem)
{:ok, session} = Session.start_link(provider: {Provider.VFS, filesystem})
```

For a Sprite, supply a trusted Sprite, an absolute root, and the exact
relative paths to read. The adapter checks file size and reads up to
1 MiB per file. Keep the approved paths and any symlink targets within
the trusted tree. This binding uses only the Sprite file adapter.

```elixir
sprite_options = %{
  mode: :borrowed,
  client: Sprites.new(System.fetch_env!("SPRITES_TOKEN")),
  name: "report-review",
  root: "/home/sprite",
  readable: ["report.html"]
}

{:ok, session} =
  Jido.Realm.Session.start_link(provider: {Jido.Realm.Provider.Sprite, sprite_options})
```

Set `mode: :owned` with an unused Sprite name to allocate a fresh Sprite.
The Sprite provider reports `:files`. Its file adapter supports read
only. Give the agent `:open`, `:read`, and `:close` for this binding.

## Share a checkout with Docker

Use a host [Realm profile](../../HOST.md#open-one-working-tree)
with a Docker image that provides Bash. Include Bash in the profile's
approved tools. Give the session `provider: {Jido.Realm.Provider.SharedCheckout,
options}` and set these provider options.

- Set `profile: profile` to a configured profile name or a profile map.
- Set `check_files: ["source.txt"]` to the complete list of source paths
  a named check uses. Put generated files outside that list.
- Set `bash: "bash"` if the image uses the default Bash executable name,
  or supply the executable approved in the profile.

The files and Bash commands share a lease. A command that can write to
the tree requires both the command's run grant and the agent's `:write`
grant. A read-only profile mounts the tree read-only. Keep other writers
out of a borrowed checkout during the lease.

With a configured store and a `:save` grant, the agent can call
`Realm.save(context, :work, verified_by: check_id)`. The save checks the
current tree against the tree recorded after the successful check.
Keep the format-1 snapshot reference and its store. To restore, give a
new session `from: snapshot` and a profile with `:import`.
[Shared checkout example](../../examples/realm/11_work_on_a_shared_checkout/README.md)

For a retained host provider, the host can use
`Jido.Realm.Host.recover_command/4` with the saved command reference.
Recovery uses the provider's existing `:status`, `:wait`, and `:stop`
operations and does not acquire a writer lease.
[Recovery example](../../examples/06_providers_and_persistent_infrastructure/06_03_recover_an_old_command/README.md)

## Add execution or services

The `:files` Profile admits file capabilities and named commands.
The `:program` Profile also admits runtimes, background execution, and
service capabilities if available.

- Lua needs a file placement with revisions, such as Local or Memory.
- Docker needs a host-approved Docker context and a cached image with the
  selected interpreter. Regular runs use staged read-only inputs and
  private scratch space. Networking defaults to disabled for these runs.
  Use a staged Local runner for named source checks.
- Apple Container needs the `container` CLI, a running system service,
  and a host-selected image. Its staged runner uses a Local workspace.
- Native preview needs erlexec, a C++ toolchain to build its helper, and
  a non-root host process with `SHELL` set. Reserve the configured loopback
  port and use an executable that honors `HOST` and `PORT`.

Use a module that implements `c:Jido.Realm.Profile.requirements/0` to
require a specific runtime or its controls. Set `:execution_controls`
on the Profile and `:capabilities` on the session to limit admission.

Run `mix jido_realm.doctor` from the package directory to check local
prerequisites. For example, use `--lane docker --strict` to fail if the
Docker lane needs attention. The Sprite lane checks for test credentials
without authenticating to the service. The Sprite lifecycle tests include
a controlled transport and an opt-in `:live_sprite` test for a dedicated
test account.
