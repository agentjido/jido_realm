# Build and revise a report

Write a setup script and a Lua program through a Jido agent. Setup creates
an input file. The program generates a report. The [agent job](example_test.exs)
uses `realm.program.run` and checks that the program cannot
read or change the protected host file. A failed run preserves the previous
report. A revised program produces new output.

The same agent job runs on Local and Memory. The Lua adapter mediates file
access and publishes drafts after a successful run.

```sh
mix test examples/realm/03_build_and_revise_a_report --trace
```
