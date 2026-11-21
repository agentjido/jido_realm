# Files

Use paths relative to the Realm root and create parent directories first.
Text operations use UTF-8. For file paths, Realm rejects empty path
components, `.`, `..`, and names that start with `.jido-realm-`. Local
also rejects symlinks. Use `.` as the root for list and search.

## Read and change files

Send these Signals to a named Realm. Include `realm` in the Signal data.

| Signal | Other data | Result |
| --- | --- | --- |
| `realm.file.create` | `path`, `content` | Creates a new file. Returns `:already_exists` if the path exists. |
| `realm.file.read` | `path` | Returns `content`. |
| `realm.file.edit` | `path`, `content` | Replaces the contents of an existing file. |
| `realm.file.delete` | `path` | Removes an existing file. |

Successful file Signals reply with `realm.file.result`. On failure, Jido
reports `:realm_file_error` with a `reason`, such as `:not_found` or
`:invalid_path`.

The following example runs in an action with an open Local or Memory
Realm, the `:tree` and `:revisions` capabilities, and `:read` and `:write`
grants. It assumes that `drafts` is a new directory.

```elixir
alias Jido.Realm

{:ok, _} = Realm.file(context, :work, :mkdir, "drafts")
{:ok, _} = Realm.file(context, :work, :create, "drafts/notes.txt", "Draft")
{:ok, %{revision: revision}} = Realm.file(context, :work, :read_revision, "drafts/notes.txt")

{:ok, _} =
  Realm.file(context, :work, :edit_revision, "drafts/notes.txt", {revision, "Reviewed"})

{:ok, %{entries: entries}} = Realm.file(context, :work, :list, "drafts")
```

If a checked edit returns `:conflict`, read the new contents and revision
before you prepare another edit. A file change can remain in the Realm
after a later step in the same Jido turn fails.

## Transfer one file

Declare each Realm name in the agent and bind it on the host. The examples
below use open `:work` and `:review` Realms. Give the action `:read` on
the source and `:write` on the destination.

```elixir
{:ok, _} =
  Jido.Realm.copy(context, {:work, "drafts/notes.txt"}, {:review, "notes.txt"})
```

`Jido.Realm.copy/3` copies one UTF-8 file to a new destination.
`Jido.Realm.move/3` also needs `:write` and `:revisions` on the source
and `:read` on the destination. It verifies the destination before it
deletes the captured source revision. If source deletion fails, it
returns `{:error, {:incomplete_move, reason}}` and leaves the copy in
place. Inspect both paths before retrying.

Use `Jido.Realm.copy_stream/4` for binary files. Both Realms must supply
`:streams`. Here `data.bin` is an existing file in `:work`.

```elixir
{:ok, _} =
  Jido.Realm.copy_stream(context, {:work, "data.bin"}, {:review, "data.bin"},
    chunk_size: 65_536
  )
```

The backend stages the stream before it publishes the destination.
The default creates a new file. Set `replace: true` to permit replacement.
