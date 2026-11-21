# Artifacts

Publish an HTML artifact when a reviewer needs a saved page and its
assets. The presenter stores a version of the selected files. The
reviewer can read the version after the Realm closes.

## Configure a presenter

On the host, start the built-in presenter. Add it to the named Realm
binding before starting the agent. This example uses the managed session
from [First Realm](first-realm.md).

```elixir
alias Jido.Realm.Artifacts

{:ok, store} = Artifacts.start_link(viewers: [:reviewer], retention_ms: 3_600_000)

bindings = %{
  work: [
    session: session,
    presenter: {Artifacts, store},
    grants: [:open, :close, :read, :write, :publish]
  ]
}
```

## Publish selected files

In a live action with the Realm open, save the page and its assets.
Then pass their relative paths to the publisher.

```elixir
alias Jido.Realm

html = ~S(<link rel="stylesheet" href="report.css"><h1>Report</h1>)
{:ok, _} = Realm.file(context, :work, :create, "index.html", html)
{:ok, _} = Realm.file(context, :work, :create, "report.css", "h1 { color: navy; }")

{:ok, artifact} =
  Realm.publish_artifact(context, :work, "index.html", ["index.html", "report.css"])
```

Publication requires `:read` and `:publish`. Each bundle can contain up
to 32 UTF-8 files and 1 MiB total. Use an `.html` entry page. Include it
in the path list along with each required asset. The presenter accepts
`.html`, `.css`, `.js`, `.json`, and `.txt`.

## Serve and revoke a version

Authenticate the viewer on the host for each request, including asset
requests. Serve the returned contents and headers from a dedicated
artifact origin. Use the artifact ID and the requested asset path for
lookup. If the host omits the path, Realm returns the entry page.

```elixir
alias Jido.Realm.Artifacts

{:ok, %{content: page, headers: page_headers}} = Artifacts.read(store, :reviewer, artifact.id)

{:ok, %{content: css, headers: css_headers}} =
  Artifacts.read(store, :reviewer, artifact.id, "report.css")
```

The view lasts for the configured retention period while the store is
running. Editing source files leaves the published version intact.
Call `Jido.Realm.Artifacts.revoke/2` with the store and artifact ID to end
access early. For a different store, implement the
`c:Jido.Realm.Artifacts.publish/3` callback.
