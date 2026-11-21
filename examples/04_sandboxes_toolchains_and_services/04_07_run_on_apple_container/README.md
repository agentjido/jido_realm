# 04.07 Run on Apple Container

Use a named profile to run a Linux command on an Apple silicon Mac with
macOS 26 or later. Start the Apple Container 1.x service (version 1.7.1 or
later) and install its default Linux kernel and init image. Make the selected
`linux/arm64` image available in the local image store. Open checks the host,
CLI, service, and image before it creates the workspace directory.
[Apple Container setup](https://github.com/apple/container/tree/1.7.1#get-started)

```elixir
config :jido_realm,
  profiles: %{
    apple_review: %{
      provider: :apple_container,
      image: "localhost/jido-realm-apple-fixture:local",
      policy: :full_access,
      store: "reports",
      tools: ["/bin/cp"],
      require: %{isolation: :container, network: :disabled, cancellation: :container}
    },
    review_in_memory: %{provider: :memory, policy: :full_access, store: "reports"}
  },
  stores: %{"reports" => "/absolute/path/to/reports"}
```

The example function copies a file. It sends the file names as literal
arguments and selects `reports today` as the working directory. The
directory is part of the workspace tree mounted at `/workspace`.
[Example function](example.ex)

```elixir
alias Jido.Realm.Host
alias Jido.Realm.Host.Examples.AppleContainer

{:ok, workspace} = Host.open(profile: :apple_review)

{:ok, snapshot} =
  try do
    AppleContainer.copy_and_save(workspace, "Reviewed report\n")
  after
    :ok = Host.close(workspace)
  end

{:ok, memory} = Host.open(profile: :review_in_memory, from: snapshot)

try do
  {:ok, "Reviewed report\n"} = Host.read(memory, "reports today/reviewed report.txt")
after
  :ok = Host.close(memory)
end
```

Each command gets its own Linux VM with only loopback networking, a read-only
root filesystem, and one workspace mount. The mount is read-only when the
profile has execute permission without write permission. Realm checks the
container configuration before start. It checks the exact container ID in the
list of all containers after a delete request. `Host.cancel/2` requests a
stop. Wait for the `Host.run/3` result to confirm cancellation before you
edit or save. If cleanup is uncertain, Realm blocks edits and saves. Close
can be tried again to complete cleanup.

Realm enforces the execution timeout after launch and the retained output
limit. The CLI requests one CPU and 256 MiB for VM sizing. Apple's overhead can
raise the guest totals, so the profile reports no enforceable CPU, memory,
process, or temporary file ceilings. Open refuses those `runtime_limits`
requirements and `stdin: :pipe`. Use a disposable workspace directory.
Apple Container profiles support file snapshots through `Host.save/1`.

Realm checks that the local image still has the same digest before each
create and verifies the digest before start. Keep the image in the local store
while the profile is in use. Apple Container 1.7.1 can fetch content during
create if local content goes away. The CLI has no local-only create option.
[Apple Container command reference](https://github.com/apple/container/blob/1.7.1/docs/command-reference.md#container-create)

## Run the live checks

Run this command with the Apple Container service available and
`alpine:latest` already cached. Use `JIDO_SANDBOX_APPLE_IMAGE` to select a
different cached Alpine image as the source for the test fixture. The tests
create and remove their own local fixture tags and temporary workspaces.

```sh
JIDO_SANDBOX_APPLE=1 mix test \
  examples/04_sandboxes_toolchains_and_services/04_07_run_on_apple_container/example_test.exs \
  --include integration
```

Before you run the profile above yourself, tag the local image with
`container image tag alpine:latest localhost/jido-realm-apple-fixture:local`.

The tests check literal arguments, file restore on memory, cancellation, timeout,
exact container removal, read-only mounts, loopback, and output truncation.
Run the simulated host and cleanup failures on any supported Elixir host with
`mix test test/jido_realm/host/apple_container_test.exs`.
