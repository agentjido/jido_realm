# 01.08 Work on a GitHub branch

## Agent job

Open a writable GitHub Realm on an approved branch. Copy a draft from a Local Realm, write and revise the final note, and remove the draft. Give a reviewer a read-only Realm pinned to the version with the final note.

## Fixture and variants

Use a test repository with a test-owned branch and a scoped subtree. Inspect branch heads, commits, and file contents independently. Repeat an edit after another writer changes the same file, then after an unrelated commit. Include a second branch and an outside path as scope checks.

## Pass conditions

- File operations publish commits to the approved branch. The observer sees the exact bytes and the removal of the draft. Other branches and paths outside the approved subtree stay unchanged.
- A stale edit reports a conflict and preserves the newer file. A change to the requested branch or repository in the file request cannot redirect the write.
- State whether revisions are scoped to a file or a branch head. With an unrelated commit, the file-scoped edit preserves the unrelated change. A branch-scoped edit reports a conflict and preserves that commit. Each successful mutation reports the resulting commit.
- The pinned Realm reads the selected version after the branch advances. Its write requests are denied. Close releases the session and leaves the branch and commits intact.

## Build on

[00.03 Open and close a Realm](../../00_profiles_and_realms/00_03_open_and_close_a_realm/README.md) · [01.02 Edit against a revision](../01_02_edit_against_a_revision/README.md) · [01.03 Copy between Realms](../01_03_copy_between_realms/README.md)

[Chapter index](../README.md)
