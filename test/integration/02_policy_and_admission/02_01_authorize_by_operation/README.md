# 02.01 Authorize by operation

## Agent job

Give a reader and a writer access to the same Realm. Ask each to read and change a note. Ask the reader to copy a file into the read-only Realm.

## Fixture and variants

Start on Local and Memory. Give each caller explicit host grants. Use a recording backend to count denied calls.

## Pass conditions

- The reader can read. Its writes and writes through transfer are denied before provider dispatch. The writer succeeds and the observer confirms that only the authorized change landed.

## Build on

[00.02 Address two Realms](../../00_profiles_and_realms/00_02_address_two_realms/README.md) · [01.03 Copy between Realms](../../01_files_and_transfer/01_03_copy_between_realms/README.md)

[Chapter index](../README.md)
