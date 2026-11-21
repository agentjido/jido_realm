# Prepare and preview an app

Write setup and application scripts through a Jido agent. The
[test runner](example_test.exs) starts an Apple Container for offline setup
and a second container for the application. The setup container can write
to the Realm tree. The test checks that it cannot see a host-only file or
environment variable or write to the guest root.

An HTTP request to the loopback preview verifies the application output.
The test stops the application and checks that the port closes. In the
rebuild, the agent starts and stops the service through Realm.

Use a running Apple Container service and a cached `alpine:latest` image.
Set `JIDO_REALM_APPLE_IMAGE` to use another cached Alpine image.

```sh
mix test examples/realm/04_prepare_and_preview_an_app --include apple_container --trace
```
