# 06.04 Allocate or reuse a Sprite

## Agent job

Open a Realm on an approved existing Sprite. Request a fresh Realm under a separate provisioning grant.

## Fixture and variants

Supply a test account, a borrowed Sprite reference and subtree, and an independent resource observer. Realm invokes the provider for both requests.

## Pass conditions

- Attach reports the exact borrowed resource and close preserves it. Fresh open produces a distinct placement. Close follows the retention policy for the test-owned Sprite.

## Build on

[06.01 Add a provider](../06_01_add_a_provider/README.md)

## Current evidence

## Run the tests

From the Realm package root, run the controlled transport case.

```sh
mix test test/integration/06_provider_lifecycle/06_04_allocate_or_reuse_a_sprite
```

To run the same case against Fly.io, set `SPRITES_TEST_TOKEN` for a
dedicated test account. The live case creates two unique Sprites and
cleans up both when the test ends.

```sh
mix test --only live_sprite
```

[Sprite provider configuration](../../../../README.md#use-a-flyio-sprite)

[Chapter index](../README.md)
