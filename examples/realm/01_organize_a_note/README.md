# Organize a note

Send one job to a Jido agent. It creates a draft in its `:work` Realm,
reads the draft, writes the final note, and removes the draft after the
final write succeeds.

```elixir
realms do
  realm :work, profile: :files
end
```

The same [agent](example.ex) runs with a Local directory or Memory store.
The [test](example_test.exs) checks the committed reply, the exact final
file contents, and the absence of the draft with a direct store reader.

```sh
mix test examples/realm/01_organize_a_note --trace
```
