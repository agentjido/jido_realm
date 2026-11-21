# 05.03 Publish a temporary route

## Agent job

Ask an agent to publish a healthy private service. Exercise the same request with and without an explicit host grant.

## Fixture and variants

Use a configured ingress provider, an independent HTTPS client, and a bounded lifetime. Exercise expiry and explicit revocation separately. Repeat expiry after stopping the Realm controller and keep the service alive for the observation.

## Pass conditions

- Without the grant, the preview stays private. With the grant, the agent can publish within its limits without another approval. The public route reaches only the permitted service. Expiry and revocation remove public access while the private service continues.
- The ingress provider enforces expiry while the controller is down.

## Build on

[02.01 Authorize by operation](../../02_policy_and_admission/02_01_authorize_by_operation/README.md) · [05.01 Start a private preview](../05_01_start_a_private_preview/README.md)

## Current evidence

[Local HTTPS access, expiry, and revocation tests](../private_preview_test.exs). The gateway checks access with the Realm session on each request.

[Chapter index](../README.md)
