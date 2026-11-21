# Realm conformance map

Jido Realm gives an agent a place to work with files and, where supported,
run untrusted code against them. Programs are files in the Realm tree.
An agent can start with an empty tree, write a program, build it if
needed, run it, and revise it. A profile declares the available
toolchains and the controls it can enforce. The same agent Signals and
result shapes apply to every profile that supports the operation.

## Agreed requirements

- File access is the minimum. The Local filesystem provider supports files.
  A profile can pair Local files with a separate runner, as the Lua showcase does.
- Providers declare their execution, service, and retention capabilities.
  Docker is a target for container execution. A Sprite can provide a
  longer-lived environment that the host can reuse.
- A durable Realm preserves its source, outputs, and setup recipe so another
  agent can reopen it. Running processes and URLs have their own lifetimes.

## Who provisions a Sprite?

| Owner | Responsibility |
| --- | --- |
| Host | Selects the provider account, credentials, placement policy, and retention. It can approve an existing resource, select one from a pool, or permit a new allocation. |
| Realm | Starts and closes the session, keeps the placement reference when the Realm is durable, and checks access and required controls before exposing the session. |
| Provider | Performs the attach or allocation using host authorization. It acquires and releases session access, reports the confirmed resource identity, and enforces the controls it claims. An allocator can be part of the provider or a host service it calls. |
| Test fixture | Supplies a controlled account or stand-in transport, a test namespace, and an independent way to inspect the resulting resource. It cleans up test-owned resources. |

Keep four identities separate. The **Realm ID** identifies the place an agent
can reopen. The **provider reference** identifies a specific resource and
tree. The **session or lease** governs current access to that tree. A
**snapshot** identifies saved bytes that can be restored.

For a live **attach** exercise, the fixture can supply the reference to a
pre-existing test Sprite and a unique subtree. Realm opens it through the
provider and tests the resulting session. For a **fresh allocation** exercise,
the fixture supplies provider configuration, and the test calls the
production Realm lifecycle to request allocation. Observe the resulting
resource by its ID. Cleanup may remove a test-owned subtree or an explicitly
test-owned allocation. Closing a session on a borrowed Sprite preserves the
machine. Test the close result before any fixture cleanup can mask it.

The current Local and Memory fixtures supply a ready backing store to the
file suite. Keep that fast setup for file conformance. For lifecycle
conformance, supply the prerequisites to the exercise and let the exercise
drive the production open and close operations.

## What a profile varies

| Dimension | Example values | Contract exercise |
| --- | --- | --- |
| Placement and ownership | Borrowed tree, new disposable resource, reused persistent resource | Attach to the exact approved reference. Close retains a borrowed resource and releases its session. A new request gets a different tree. |
| File storage | Local, Memory, Sprite tree, GitHub, object store | Round-trip exact bytes, reject duplicate creates, preserve contents on failure, and verify effects directly in the selected store. |
| Tree access from compute | Same tree, mounted tree, explicit copy with a publish step | Write through the file API, change the file from a command, and check visibility at the point the profile promises. A copy profile must detect an intervening source change before publishing. |
| Program toolchain | Lua, Bash, Python, JavaScript, a source compiler and runtime for a WASI target | Discover a supported toolchain. Author a program in the tree, run it, and repeat after changing the source. |
| Execution transport | In-process runner, container exec, SSH to a managed host | Check literal arguments, working directory, and run outcomes. With SSH, verify host identity and recovery after a lost connection. |
| Execution boundary | Docker, Apple Container, Sprite, embedded Lua VM, Wasm runtime | Verify each claimed isolation, network, process, and resource control from inside the runner. |
| Named command access | Direct agent call, Lua or Bash bridge | Discover a host-approved handler and check its argument and file grants at each entry point. |
| Caller policy | Reader, writer, executor, lifecycle operator | The host grants each operation and Realm checks it before dispatch. A denied operation leaves the store unchanged. Scope grants to the Realm ID when attachments are introduced. |
| Continuity and recovery | Ephemeral tree, same target, snapshot restore, lost reply | Reopen the expected tree. Resume allocation lookup after a lost reply. Block new writers and saves while an old writer can still act. |
| Service access | Disabled, private preview, public HTTPS | Start an agent-written service on an assigned port. Wait for readiness. Check each access policy and confirm that stop and expiry revoke the route. |
| Optional capabilities | Search, streamed I/O, snapshots | Run a separate contract for each advertised capability. A profile fails admission if a required control is unavailable or unknown. |

Run representative profiles against these contracts. Some providers bind
several dimensions together. Select profiles that demonstrate a new
guarantee or an interaction, such as a read-only tree under a native runner.
A Sprite profile can start with files only. Adding Bash adds command and
containment exercises to that profile. The file assertions still apply.

## Author, run, and revise a program

The host approves the toolchain and sets the limits. The agent writes the
source and selects its entry point in the Realm. Apply the untrusted-code
boundary to agent-written and imported code, including build steps,
dependency hooks, tests, and subprocesses. The profile reports which
toolchains can run source, build artifacts, and run the resulting artifacts.
The agent starts a program with `realm.program.run`. Keep
working directories, arguments, run IDs, diagnostics, and terminal outcomes
consistent across toolchains. The profile declares file visibility and the
effect of failures and cancellation.

The first shared program exercise starts with an empty tree.

1. Discover a toolchain that can run agent-authored source. Write a small
   report program with an entry point, a helper file, and example input
   through Realm file operations.
2. Build the program if the toolchain requires it. Run the entry point.
   Check the exit status and output, then read the report through Realm.
   The fixture independently confirms that the selected store contains it.
3. Introduce a source error and check that the run reports a failure with
   diagnostics. Repair the source and change the helper's output. Build
   again if needed and verify that the next run produces the new report.

The fixture supplies the environment, toolchain, and store observer. Each
language variant supplies source for the same report exercise. The agent
writes that source during the test. All variants check the same report,
failure, and revision behavior.

| Profile | What it adds to the shared exercise |
| --- | --- |
| Bash, Python, and JavaScript in Docker | The entry point loads a declared helper. The interpreter sees a read-only input tree. The agent can save the output through the file API. |
| Lua with Memory | The entry script uses a helper through a Realm-scoped loading mechanism. Prove the loader and mediated file functions stay within the tree. Test staged writes and publication on success. The Realm Lua example provides a starting point for mediated files and limits. [Realm Lua example](../examples/04_sandboxes_toolchains_and_services/04_05_evaluate_an_embedded_runtime/README.md) |
| WASI with Wasmtime | The agent writes source, invokes a supported compiler, and runs the artifact it just produced. Verify what the build step can access separately from the guest. Give the guest only the necessary tree access. [Wasmtime directory capabilities](https://docs.wasmtime.dev/api/wasmtime_wasi/struct.WasiCtxBuilder.html) |

Extend the exercise when a profile claims more. Examples include running
the program's tests, using an approved dependency source, reopening and
rerunning the project, and starting a service from the program.

## Setup and service previews

Amp Orbs prepare an environment with a setup script, support a separate
resume hook, and route traffic to a service that listens on an assigned
port. This gives Realm three contracts to test. [Amp setup](https://ampcode.com/docs/orbs/customizing), [Amp portals](https://ampcode.com/docs/orbs/portals)

| Contract | Pass condition |
| --- | --- |
| Setup | Run the approved recipe with the declared network and file permissions. A successful setup produces a usable environment. A failed setup blocks ready status and leaves no reusable setup result. Reuse a saved result only when the recipe, inputs, toolchain and required policy match. |
| Service | Run the agent's program with an assigned `PORT`. A service reaches ready status only after the host confirms that it responds on that port. On failure, return diagnostics. Stopping the service closes its listener and route. |
| Public access | Require a host grant for the selected service and an expiry time. Before approval, anonymous clients cannot reach the service. After approval, an independent client can reach the selected port over HTTPS. Other ports stay closed. Revoke the route on expiry or explicit unpublish while the service can still run privately. Test loss of the controller and eventual route expiry. |

The Apple showcase runs two real containers against the same Realm tree.
Setup runs offline. The application container inherits the setup files and
exposes a loopback-only preview. The test checks the returned content and
the effect of stopping the container. Public HTTPS requires a configured
ingress provider and its own test. [Apple Container port forwarding](https://github.com/apple/container/blob/main/docs/networking.md#forward-traffic-from-localhost-to-your-container)

## How to test security

1. **File boundary.** Run the base file suite on each writable profile. Reject
   invalid paths and host binding options in Signals. Open two stores and
   verify that each agent only sees its own tree. Keep backend-specific
   checks such as Local symlink confinement next to the backend.
2. **Caller authorization.** Run the same file profiles with a trusted
   read-only grant. Seed a file through a separate authorized setup call.
   Read must succeed. Create, edit, and delete must fail with a stable
   policy error. Check existing bytes and absence of new files with the
   observer. Add a recording provider case to prove denied calls never
   reach the provider. Try putting a write grant in the Signal and verify
   that it conveys no permission.
3. **Capability admission.** Configure a required control and test a provider
   that reports it as supported, unsupported, or unknown. Only confirmed
   support permits a session to become ready. If the provider already
   acquired a lease, check that failed admission releases it and preserves
   any borrowed resource.
4. **Runtime enforcement.** For profiles that support untrusted code, use
   the real runtime and a program written through the Realm file API.
   First verify that it can read or write an allowed file. Then verify that
   it cannot access an outside sentinel, change a read-only tree, reach a
   controlled endpoint when networking is disabled, or read a host-only
   test credential. Select probes for the controls the profile claims.
   Observe the result and the protected state through the fixture. Verify
   that a confirmed stop leaves no running writer.

## Test build order

The [integration ladder](../test/integration/README.md#build-order)
gives the build order. Its [binding matrix](../test/integration/README.md#required-binding-cases)
defines the required cases for each backend and execution combination.

Local and Memory file jobs run through the Realm plugin. The program
cases use Realm Signals to run Lua, Bash, Python, and JavaScript. The
shared coding case uses the production runner on Docker and Apple
Container and a test gateway for private review. [Coding integration case](../test/integration/09_model_driven_files/README.md)

## Realm references

- [Provider contract](../lib/jido_realm/host/provider.ex) separates controller policy, provider enforcement, acquisition, and release.
- [Persistent infrastructure decision](decisions/2026-11-19-persistent-infrastructure.md) separates the resource, session, and snapshot lifetimes and defines the two conditions for writer takeover.
- [Machine reuse example](../examples/06_providers_and_persistent_infrastructure/06_02_reuse_or_request_a_machine/README.md) checks stable identity, fresh placement, and retention.
- [Policy exercises](../examples/03_security_and_policy/03_01_authorize_by_operation/example_test.exs) check grants independently and include a real read-only runner check.
- [Realm v1 allocation](../../jido_realm_v1/lib/jido/realm/provider.ex) delegates fresh placement to a host-configured allocator with an idempotency key.
