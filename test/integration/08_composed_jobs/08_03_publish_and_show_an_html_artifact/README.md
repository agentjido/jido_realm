# 08.03 Publish and show an HTML artifact

## Agent job

Ask an agent to make an HTML report with a chart or a table filter and
show it to the reviewer. The report has an entry page, a stylesheet,
and a script. The agent returns a reference that the host can display
in the review interface.

## Fixture and variants

Use the same report and assertions with managed Local and Memory file
bindings. Supply an approved artifact presenter, a browser, and two
review identities. Give one identity permission to open the published
output. Repeat the case with the HTML report from the
[coding job](../08_02_build_test_and_hand_off/README.md).

## Pass conditions

- The agent writes the report through Realm and publishes the selected
  files under a host grant. The result identifies a specific version
  and its HTML entry point. Denying the publish grant produces no
  viewable artifact.
- An authorized reviewer opens the result. An independent browser test
  checks visible content and a change after interaction. Only the
  approved files are available. A second reviewer with network access
  cannot read the entry page or the assets without permission.
- The host executes the report's script in an isolated browser context.
  The test verifies that the report cannot read the reviewer's host
  session or reach files outside the published bundle.
- A retained artifact still opens after the agent closes its Realm
  session. Later edits to the source files leave the published version
  intact. Expiry or revocation ends access according to the host policy.

## Build on

[00.03 Open and close a Realm](../../00_profiles_and_realms/00_03_open_and_close_a_realm/README.md) · [02.01 Authorize by operation](../../02_policy_and_admission/02_01_authorize_by_operation/README.md)

## Run the cases

The default tests use owned Local and Memory Realms with the built-in
presenter. They check versioning, grants, revocation, and bundle limits.
The browser lane starts a loopback host and opens the report after Realm
close. It checks the stylesheet, button interaction, and browser isolation.
Use Node.js 22 or later and Chrome or Chromium. Set `JIDO_REALM_CHROME`
if the browser is at a custom path.

```sh
mix test test/integration/08_composed_jobs/08_03_publish_and_show_an_html_artifact
mix test test/integration/08_composed_jobs/08_03_publish_and_show_an_html_artifact --only browser
```

[Chapter index](../README.md)
