# 08.01 Copy to a sandbox and preview

## Agent job

Give one agent a Local workspace and an execution Realm. Ask it to write a page locally, copy the page, and start a private preview in the execution Realm.

## Fixture and variants

Run Local to a local container, then Local to a borrowed Sprite. Use the same app and agent job with both bindings. Supply a unique page for each attempt, the approved destination binding, and independent HTTP and file clients. Repeat with a denied destination write.

For the coding variant, start the application from the repository in
[08.02](../08_02_build_test_and_hand_off/README.md). Give the agent one
review comment about the page. Ask it to make the change, rerun the
tests, and show the revised application through the private preview.

## Pass conditions

- The source retains the page. The target contains the exact same bytes. The authorized preview returns those bytes over HTTP after readiness. An unauthorized client cannot reach the preview.
- A denied copy leaves the target unchanged and starts no service. Service stop closes its listener and route. Closing the Realm applies the destination's retention policy.
- In the coding variant, a browser sees the expected change after the
  application reloads or the service restarts. The reviewer still needs
  permission to reach the new version.

## Build on

[01.03 Copy between Realms](../../01_files_and_transfer/01_03_copy_between_realms/README.md) · [05.01 Start a private preview](../../05_services_and_routes/05_01_start_a_private_preview/README.md). The Sprite variant also uses the borrowed placement from [06.04 Allocate or reuse a Sprite](../../06_provider_lifecycle/06_04_allocate_or_reuse_a_sprite/README.md).

## Current evidence

[Docker copy, preview, and page revision tests](../../05_services_and_routes/private_preview_test.exs)

[Local and Memory copy example](../../../../examples/realm/02_copy_between_realms/README.md) · [Apple Container preview example](../../../../examples/realm/04_prepare_and_preview_an_app/README.md)

[Chapter index](../README.md)


## Checked app pressure test

The opt-in test uses the Phoenix and TypeScript fixtures from the container
cases. The Realm keeps the source in an owned Local placement. The tests use
`sprites-ex` to create each Sprite, upload the checked snapshot, run the
check and service, and delete the Sprite.

Use an approved `SPRITES_TEST_TOKEN` and a Sprites CLI signed in to the same
organization. Set `SPRITES_TEST_ORG` if the CLI needs an explicit organization.
The CLI supplies loopback TCP forwarding. The Elixir SDK supplies resource,
file, and command operations. The Sprite needs Node with type stripping or
the Elixir and Erlang versions that the Phoenix fixture requires.

```sh
mix test test/integration/05_services_and_routes/sprite_apps_test.exs --only live_sprite --max-cases 1
```

The test checks the response before and after route revocation. It also checks
the process ID and process start time inside the Sprite. The test deletes
only the two disposable Sprites it creates and checks for a missing resource
response after each deletion.
