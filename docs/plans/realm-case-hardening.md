# Realm conformance hardening

Scope completed before chapter 03. The checks use the ExUnit ladder with live
Jido agents. Program execution, service routes, and live cloud accounts
are outside this work. Keep `realm_case` in test support.

| Step | Work | Done when |
| --- | --- | --- |
| 1. Use one Profile for managed file jobs | Resolve the requirements named in the agent DSL. Run the existing note and copy jobs through managed Local and Memory bindings. | The same Profile and assertions apply to both backends. Each case opens and closes through Realm. Missing required capabilities fail before any file dispatch. |
| 2. Make the fixture contract explicit | Give fixtures a clear role for binding, seeding, observing, and cleanup. Report each case and binding separately. Label real stores and controlled transports in test output. Consolidate repeated agent setup after the numbered suite has equivalent checks. | A new binding can run the existing job without edits to its body. A missing required binding or capability fails the case. A missing opt-in service is reported separately. Expected outcomes come from the case. |
| 3. Check session loss and uncertain outcomes | Extend the close and conflict cases with a held operation, owner loss, and cleanup or reconciliation. Use a barrier to control when the operation can finish. | Dead sessions cannot admit work. Owned resources are released when safe. Borrowed resources survive. If a write might have reached the store, the result stays unknown pending reconciliation. No write is replayed on a lost reply. |
| 4. Check file and transfer edge cases | Define which revision guarantees require generation changes, including an edit that restores old bytes. Cover destination contention and interrupted streams. Use direct store observations for all failed operations. | The scope of each revision token is explicit. Stale writes follow that contract. Interrupted transfers preserve prior data and leave no partial publication. A denied transfer dispatches neither side. |
| 5. Verify one VFS-backed binding | Run a managed Memory file case through the VFS provider with an independent observer. | The same note and copy checks pass, including exclusive create and explicit edit. Only tested capabilities are advertised. Record any VFS changes required for a second binding. |

## Review findings that drove the scope

- The old DSL checked a Profile name against a host-supplied label.
  The plugin now resolves the declared requirements. [Plugin](../../lib/jido_realm/plugin.ex)
  · [Session](../../lib/jido_realm/session.ex)
- The old session monitored operation workers without a shutdown path.
  Cases now cover lease owner exit, a lost write reply, and normal
  session shutdown. If source shutdown drops a transfer reply after the
  destination saved the file, the result stays unknown.
  [Session](../../lib/jido_realm/session.ex)
  · [Close during work](../../test/integration/00_profiles_and_realms/00_04_close_during_work/README.md)
  · [Stream a large file](../../test/integration/01_files_and_transfer/01_05_stream_a_large_file/README.md)
- Local and Memory revisions hash file bytes. A file changed back to its
  earlier contents has its earlier revision. [Revision helper](../../lib/jido_realm/files/tree.ex)

## Dependency decisions

**VFS is the first adapter candidate.** Reuse its file views, adapter
capability checks, and streaming. Keep Realm grants, revision conditions,
and transfer results in Realm. VFS Local writes can replace files.
The S3 delete interface has no revision argument. The GitHub adapter
reads from its configured ref but omits the branch from write and delete
requests. GitHub uses the default branch for those requests. Before a
writable binding passes 01.08, it must direct each mutation to the approved
branch, use the caller's expected SHA, and return the commit identity.
[Local](../../../jido_vfs/lib/jido_vfs/adapter/local.ex)
· [S3](../../../jido_vfs/lib/jido_vfs/adapter/s3.ex)
· [GitHub](../../../jido_vfs/lib/jido_vfs/adapter/github.ex)
· [GitHub Contents API](https://docs.github.com/en/rest/repos/contents)

**Shell is a candidate for the first Lua binding in chapter 03.** It can
attach a session to a caller-owned VFS. Its Lua bridge calls Shell
commands. A Realm binding must enforce Realm file grants at that
boundary and prove which tree the program reads and writes.
[Shell sessions](../../../jido_shell/lib/jido_shell/shell_session.ex)
· [Lua backend](../../../jido_shell/lib/jido_shell/backend/lua.ex)

The [Realm VFS provider](../../lib/jido_realm/provider/vfs.ex) runs the
managed note and copy cases with VFS Memory in the main suite. Realm pins
VFS to a commit that supplies atomic captures and checked edits.

An isolated Mix project compiled Realm with the local Shell and VFS
checkouts. Mix required the direct Lua dependency to lose its test-only
restriction because Shell needs Lua at runtime. A Lua call through Shell
read a file from a borrowed VFS Local tree. All 55 active Realm tests
passed with both packages loaded. This probe used Shell `3c585dd` and
VFS `e2d2922`. Release constraints still need verification.
