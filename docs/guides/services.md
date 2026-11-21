# Services

A service is a process. An endpoint is a route through a host gateway to
that process. Realm starts a service and checks HTTP readiness before it
returns the service ID. The agent can then request an endpoint.

## Register a service

Use an owned Local session with the `:program` Profile. Start with the
[named check](exec.md#run-a-named-check) configuration. In the staged
runner options, set `files: ["verify.ts", "server.ts"]` so that the check
and service use the same files. Set `network: "bridge"` for the Docker
preview. Pass that adapter in both the `runners` map and the following
session options.

```elixir
service_options = [
  preview: adapter,
  preview_base_url: "https://review.example.org/preview",
  preview_viewers: [:reviewer],
  services: %{
    site: %{
      exec: {:entrypoint, :javascript, "server.ts"},
      ports: %{http: 4173},
      require_check: :verify,
      options: [timeout_ms: 15_000]
    }
  }
]
```

Set the base URL to the address of your gateway. The gateway authenticates
each viewer, calls `Jido.Realm.Preview.target/3` with the session, endpoint
ID, and authenticated identity, and forwards the request only if Realm
returns a target.

## Start and expose the service

Before running the named check, save these contents as `server.ts` in the
Realm. The adapter supplies `PORT` and checks for HTTP success at `/`.

```typescript
import { createServer } from "node:http";

createServer((_request, response) => {
  response.writeHead(200, { "Content-Type": "text/plain" });
  response.end("Realm service");
}).listen(Number(process.env.PORT), "0.0.0.0");
```

After the check succeeds, use its run ID as `check_id` in the action.
Start needs `:read`, `:run`, and `:service`. Stop needs `:service`.
Grant `:expose` for private endpoints.

```elixir
{:ok, service} = Jido.Realm.start_service(context, :work, :site, verified_by: check_id)
{:ok, endpoint} = Jido.Realm.expose_port(context, :work, service.id, :http)

:ok = Jido.Realm.close_port(context, :work, endpoint.id)
:ok = Jido.Realm.stop_service(context, :work, service.id)
```

The staged adapter checks that the files and toolchain still match the
successful check. If the source changes, run a new check.

## Control endpoint lifetime

A service starts without a gateway route. Closing an endpoint leaves the
service running. Stopping the service or closing the Realm revokes its
endpoints. The gateway also denies requests when the service process exits.
Current adapters support one running service and one configured HTTP port
per session.

For temporary anonymous access, configure a separate HTTPS gateway with
`:preview_public_base_url` and set `:preview_max_public_ms`. Give the
binding `:publish_preview` in addition to `:expose`. To open the public
endpoint, pass `access: :public` and a bounded `ttl_ms:` to
`Jido.Realm.expose_port/5`. The gateway calls
`Jido.Realm.Preview.public_target/2` on every request to check expiry.
Expiry ends access to the public endpoint. The service and any private
endpoint can stay active.

Realm also supports trusted native services. A native adapter runs a
host-approved executable with the host user's privileges. Keep the
executable and its configuration outside agent-writable paths. See
[Providers](providers.md) for host prerequisites. To share saved HTML
after the Realm closes, use an [artifact](artifacts.md).
