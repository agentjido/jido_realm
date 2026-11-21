# 01.02 Edit against a revision

Local and Memory use content revisions. A token matches when the current
bytes match the bytes it represents, including after an edit restores
those bytes. A binding that promises to detect every write needs a
generation token.

## Agent job

Let two authorized agents read the same note. Ask each to apply a different edit against the revision it read.

## Fixture and variants

Use Local and Memory profiles that declare revision-aware edits. Coordinate the two reads so both agents start from the same revision.

## Pass conditions

- Exactly one edit succeeds. The other caller gets a conflict and can read the newer revision. The observer sees the winning bytes.

## Build on

[00.01 Organize a note](../../00_profiles_and_realms/00_01_organize_a_note/README.md)

[Chapter index](../README.md)
