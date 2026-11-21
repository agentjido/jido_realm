# Model-driven file work with Qwen

This opt-in test runs a live `Jido.AI.Agent` with the ReAct reasoning flow and
`Jido.Realm.Plugin`. Qwen selects and supplies the arguments for the
`realm_file` tool. The tool calls `Jido.Realm.file/5` with the action context.

The host binds `source` with read access and `work` with read and write access.
The agent reads a unique UTF-8 note, creates and edits a report, removes a stale
draft, and tries one write to the read-only source. The test checks the ordered
tool calls, the permission denial, and the exact stored files through independent
readers. Each trial starts a fresh agent and two fresh stores.

## Run locally

Start the LM Studio API on loopback and load a downloaded Qwen model. These
commands use the Qwen 3.8 27B model and the test's default model identifier.

```sh
lms server start --bind 127.0.0.1 --port 1234
lms load qwen/qwen3.8-27b --identifier qwen3.8-27b-realm --context-length 8192 --parallel 2
```

Run one trial per backend from the Realm directory.

```sh
mix test test/integration/09_model_driven_files/file_agent_test.exs --only lmstudio --max-cases 1
```

The script runs the same test. Its arguments set the number of trials per
backend and the maximum number of concurrent trials. Every passing trial
prints its backend, elapsed time, and model call count. ExUnit reports
failures and returns a nonzero exit code if a trial fails.

```sh
./scripts/pressure_realm_files.sh 5 2
```

Set `JIDO_REALM_LMSTUDIO_MODEL` to use a different loaded model identifier.
The test uses `http://127.0.0.1:1234/v1`. If the server requires a token, set
`LMSTUDIO_API_KEY` in your environment. The default test suite excludes the
`:lmstudio` tag.

## Edit one Phoenix project in a Realm

The shared coding case runs on Docker and on Apple Container. The Jido agent
runs on the host. It uses the Realm tools to read and edit a single Local
placement. Each check uses an offline guest with a read-only snapshot and
private scratch space. The host starts the service with the run ID of a successful `:verify`
command. Both engine adapters compare the snapshot used for the service to
the checked source. The host opens a separate gateway endpoint. The test
gateway serves the endpoint at its own loopback origin and authorizes each
request.

The coding profile registers `glob`, `grep`, `read`, `write`, `edit`, and
`run_check`. Include a string Realm name in each call when the agent
declares named Realms. The host can also register `bash` for a binding
that admits guest commands. Trusted native services use the existing
erlexec adapter.

Build the fixture image and load the same image into both engines on an
Apple silicon Mac. The build uses the pinned base image and Mix lockfile
to prepare dependencies. The test guests do not download dependencies.

```sh
container system start
export JIDO_REALM_CODING_IMAGE=jido-realm-coding:local
docker build --platform linux/arm64 -t "$JIDO_REALM_CODING_IMAGE" \
  test/integration/09_model_driven_files/apple_edit_fixture
docker save "$JIDO_REALM_CODING_IMAGE" -o /tmp/jido-realm-coding-image.tar
container image load -i /tmp/jido-realm-coding-image.tar
docker network create jido-realm-coding-preview-local
JIDO_REALM_BASH_IMAGE="$JIDO_REALM_CODING_IMAGE" mix jido_realm.doctor --lane docker --strict
JIDO_REALM_APPLE_IMAGE="$JIDO_REALM_CODING_IMAGE" mix jido_realm.doctor --lane apple_container --strict
mix test --include docker --include browser
mix test --only apple_container --max-cases 1
```

The service suite also checks a TypeScript app on port 4173 with the cached
arm64 `node:22-alpine` image. Import it into Apple Container with
`docker save` and `container image load` if needed. Both suites use the same
`exec`, `start_service`, `expose_port`, `close_port`, and `stop_service`
calls.

Start LM Studio on loopback as shown above. Load the model and run the live
case. Three successive turns add an introduction, a tested JSON endpoint,
and a custom 404 page. The third turn must see the same acceptance check
fail before the edit and pass after it. The host runs the project and the
read-only acceptance suite after each turn.

```sh
lms load qwen/qwen3.8-27b --identifier qwen3.8-27b-realm --context-length 16384 --parallel 1
mix jido_realm.doctor --lane lmstudio --strict
mix test test/integration/09_model_driven_files/apple_edit_agent_test.exs --only lmstudio --max-cases 1
```

The evidence directory is `tmp/apple-edit-evidence/<run-id>/`. It contains
one JSON tool trace for each turn, before and after manifests, exact diffs,
test output in `guest-runs.jsonl`, and route and workspace cleanup records.

Set `JIDO_REALM_APPLE_EDIT_BROWSER=1` to hold each preview for browser
review for up to 120 seconds. Round 0 is the baseline. Open `browser_url`
from `preview-<round>.json` to establish the viewer session. Check the
home page, the JSON endpoint starting in round 2, and the custom 404
and its link home in round 3. Write a JSON object with the preview's
`url` and `"verified": true` to `browser-<round>.json` after each review.
The test stops the service and verifies that the route and its guest
port close.
