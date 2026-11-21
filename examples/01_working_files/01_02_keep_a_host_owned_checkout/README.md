# 01.02 Keep a host-owned checkout

Edit a file in a Git checkout and read it with a Docker command. Close the
workspace and use Git on the host to review the edit.

Set the absolute directory path in a named profile. Use a checkout that the
host can give to the program for the duration of the workspace.

```elixir
config :jido_realm,
  profiles: %{
    review: %{
      provider: :docker,
      image: "alpine:3.20",
      checkout: "/var/lib/my_app/review",
      policy: :full_access,
      require: %{isolation: :container, network: :disabled}
    }
  }
```

Once the profile and a checkout with `draft.txt` are ready, run the same file
and command calls as in the disposable workspace example.

```elixir
alias Jido.Realm.Host

{:ok, workspace} = Host.open(profile: :review)

try do
  :ok = Host.write(workspace, "draft.txt", "Revised draft\n")
  {:ok, %{exit_status: 0, output: "Revised draft\n"}} =
    Host.run(workspace, ["cat", "draft.txt"])
after
  :ok = Host.close(workspace)
end
```

A successful close removes the containers and releases the checkout.
The checkout stays on disk with its edits. Reopen it with the same profile to
continue. The host manages Git status, commits, and cleanup.

## Failure and recovery

- Set `checkout:` only for an existing native directory. Open refuses a
  missing path, a file, or a symbolic link at the directory path.
- Open refuses `from:` with a checkout profile. Use a disposable profile
  to restore a snapshot. If the checkout has a configured store, `save/1`
  captures the full tree, including hidden files such as the Git metadata.
- Docker keeps a reservation for the directory until cleanup is confirmed.
  Open returns `:checkout_busy` if a reservation or command remains. This
  includes a second profile that uses another path to the same directory.
- After controller loss, the host can inspect the containers, let a command
  finish, or stop it. Inspect the containers with the
  `dev.jido.realm.checkout` label. The command and its
  `jido-checkout-*` reservation share a `dev.jido.realm.sandbox` label.
  Remove the reservation only after all command containers for that sandbox
  have been removed and the controller can no longer start a command.

The reservation applies to Realm on the same Docker engine. The host
coordinates its own edits, processes outside Realm, and other engines.
Keep the directory path in place while it is open. Realm can detect a
replaced directory at the start of an operation.

## Run the example

Use a local Docker engine, Git, and an installed Alpine image. The tests
create their own checkout and containers. They use a command barrier to
test controller loss. The gVisor and full BEAM restart cases need separate
provider tests.

```sh
JIDO_SANDBOX_DOCKER=1 JIDO_SANDBOX_IMAGE=alpine:3.20 \
  mix test examples/01_working_files/01_02_keep_a_host_owned_checkout/example_test.exs --include integration --warnings-as-errors
```
