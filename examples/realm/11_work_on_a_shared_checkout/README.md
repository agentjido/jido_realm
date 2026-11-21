# 11 Work on a shared checkout

A host gives a Jido agent a checkout and a named Bash check. The agent
edits the source with a revision check. Docker reads that edit and writes
a report into the checkout. The agent reads the report and saves the
checked tree. A second, read-only agent opens that saved revision in a
fresh BEAM and reads the original report. It also runs the check to verify
that Docker prevents writes to the restored tree.

The host sets the Realm profile, the snapshot store, and the source
paths that the check covers. The Docker mount and the Realm file API use
the same tree. Keep other writers out of the checkout while the Realm
is open. If a file changes after a check passes, a save that references
that check fails until the agent runs the check again.

Start a local Docker engine and make the `bash:5.2` image available. Then
run this command from the repository root.

```sh
mix test examples/realm/11_work_on_a_shared_checkout/example_test.exs --include docker
```

[Example code](example.ex) · [Tests](example_test.exs) ·
[Host setup](../../../docs/guides/providers.md#share-a-checkout-with-docker)
