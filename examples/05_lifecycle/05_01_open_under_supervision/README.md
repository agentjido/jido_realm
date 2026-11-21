# 05.01 Open under supervision

Use `Host.open/1` with `owner:` to give a profiled workspace a
longer life than the call that creates it. Use a process from the host
supervision tree as its owner. Keep a saved snapshot reference if you need
to recover the report after that process exits. [Example](example.ex)

```elixir
alias Jido.Realm.Host

{:ok, owners} = Task.Supervisor.start_link()
{:ok, owner} = Task.Supervisor.start_child(owners, fn -> Process.sleep(:infinity) end)
{:ok, workspace} = Host.open(profile: :memory, owner: owner)
:ok = Host.write(workspace, "report.txt", "Saved")
{:ok, snapshot} = Host.save(workspace)
:ok = Host.write(workspace, "report.txt", "Unsaved edit")
:ok = Task.Supervisor.terminate_child(owners, owner)
```

After the Realm controller stops, read, write, and save on the old
handle return `:closed`. Reopen the saved tree under a live owner.

```elixir
{:ok, reopened} = Host.open(profile: :memory, from: snapshot)
{:ok, "Saved"} = Host.read(reopened, "report.txt")
:ok = Host.close(reopened)
```

Run the same calls with the Docker profile to use a disposable container.
The host must configure both profiles and the snapshot store. An exited
owner is refused with `:owner_unavailable` when opening a profiled
workspace. [Profile and store setup](../../README.md#save-and-reopen-after-a-beam-restart)

## Run the tests

```sh
mix test examples/05_lifecycle/05_01_open_under_supervision/example_test.exs --include integration
JIDO_SANDBOX_DOCKER=1 JIDO_SANDBOX_IMAGE=alpine:3.20 mix test examples/05_lifecycle/05_01_open_under_supervision/example_test.exs --include integration
```

The tests stop a supervised owner and kill a Realm controller while its
owner stays alive. Memory releases the mounted tree. Docker removes the
container and its workspace directory. The controller-exit test checks
that the Docker command is running before it kills the controller. Both
providers can reopen the last saved report. [Tests](example_test.exs)

## API fit and gaps

Use the same Realm calls on both providers. The test harness inspects
the local provider to verify cleanup after the controller exits. A
`:closed` error shows that the handle has expired. Provider cleanup can
finish later. These tests keep the BEAM and Docker engine running during
cleanup. [Close while work is running](../05_02_race_close_with_work/README.md)
