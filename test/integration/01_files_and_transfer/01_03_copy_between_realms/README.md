# 01.03 Copy between Realms

## Agent job

Give one agent a draft in one Realm and ask it to create a review copy in another.

## Fixture and variants

Run Local to Memory and Memory to Local. Repeat with a remote or object-backed target when it meets the same file contract.

## Pass conditions

- Independent readers verify the exact bytes on both sides. A repeat copy to an occupied destination reports a conflict and preserves the existing copy.
- Deny source read and destination write in separate attempts. Each denial leaves the destination unchanged.

## Build on

[00.02 Address two Realms](../../00_profiles_and_realms/00_02_address_two_realms/README.md)

## Current evidence

The example composes read and create in an agent action and checks a destination conflict. [Copy example](../../../../examples/realm/02_copy_between_realms/README.md)

[Chapter index](../README.md)
