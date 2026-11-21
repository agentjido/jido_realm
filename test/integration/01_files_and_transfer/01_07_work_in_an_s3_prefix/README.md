# 01.07 Work in an S3 prefix

## Agent job

Open an S3 file Realm, organize a note, and copy the result to a Local Realm. Try to replace or remove the note at a stale revision in two separate attempts.

## Fixture and variants

Give the binding an approved bucket and a test-owned prefix under a borrowed bucket. Seed a sentinel under an adjacent prefix with a similar name. Use a direct S3 client to inspect object bytes and versions. In one run, let the write complete and lose its reply.

## Pass conditions

- The note job uses the standard file operations. The Local copy matches the object bytes. The draft is absent from the current view.
- A duplicate create reports a conflict. A stale edit or delete preserves the newer object. The adapter reports the result of each operation without assuming a multi-object transaction.
- The agent reports the unknown outcome. When the provider can confirm the write, reconcile the original request without overwriting a newer object.
- A caller cannot reach the sentinel or change the bucket or prefix through a file request. Close releases the session and retains the approved prefix under the configured retention policy. The observer checks this before fixture cleanup.

## Build on

[00.03 Open and close a Realm](../../00_profiles_and_realms/00_03_open_and_close_a_realm/README.md) · [01.02 Edit against a revision](../01_02_edit_against_a_revision/README.md) · [01.03 Copy between Realms](../01_03_copy_between_realms/README.md)

[Chapter index](../README.md)
