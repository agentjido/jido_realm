# 04.07 Mount read-only inputs

## Agent job

Read a host-provided reference file through Realm. Run a program that reads the same reference and writes a report into the writable workspace. Try to change the reference through both paths.

## Fixture and variants

Give the binding a borrowed input tree and a separate writable tree. Bind the inputs at a declared relative path. Use independent readers on both stores. Start with mediated files, then repeat on a native binding that offers read-only mounts.

## Pass conditions

- File reads and program reads see the same reference bytes. The expected report appears in the writable tree.
- The file interface and the program deny changes to the input tree. The fixture confirms its bytes are unchanged.
- Closing the Realm releases its access. The borrowed input tree remains available to its owner.

## Build on

[02.01 Authorize by operation](../../02_policy_and_admission/02_01_authorize_by_operation/README.md) · [04.01 Confine code to approved files](../04_01_confine_code_to_approved_files/README.md)

## Current evidence

Shell can attach caller-owned filesystems. Realm must also prove read-only access through both interfaces. [Shell mount table](../../../../../jido_shell/lib/jido_shell/vfs/mount_table.ex)

[Chapter index](../README.md)
