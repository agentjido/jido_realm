# Copy between Realms

Give one Jido agent two named Realms. It reads a draft in `:source` and
creates a review copy in `:target`. The [agent](example.ex) uses the same
file interface on both sides. The host can swap Local and Memory without
changing the job.

The [test](example_test.exs) verifies exact bytes in both stores. It then
edits the source and repeats the job. The occupied destination rejects
the copy and retains the previous version.

```sh
mix test examples/realm/02_copy_between_realms --trace
```
