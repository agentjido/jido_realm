# Realm coding agent workbench

This single-page Phoenix app runs a Jido coding agent against two build recipes
on four providers. Select one case or use **Run all eight builds**. Select a
result to see the build log, generated source, and live preview.

Each case starts with its own project directory. The agent declares a
`:program` Realm in its DSL. Inkling returns complete file edits as JSON. The
agent writes and reads those files through Realm and invokes a host-approved
command to install, build, and start the app. It sends build errors back to
Inkling for up to four attempts. A preview passes after its own port returns
HTTP 200 with the expected content.

- Phoenix uses its own Mix project, Phoenix router and endpoint, and Bandit.
- The TypeScript landing page uses erasable types and Node's HTTP server.

## Run

From this directory on Elixir 1.18 or later, install the dependencies and start
the workbench.

```sh
mix deps.get
WORKBENCH_SPRITE=my-test-sprite mix phx.server
```

Open [the local workbench](http://127.0.0.1:4090/). It uses
`http://127.0.0.1:1234/v1` and model `inkling-2-mini` by default. Set
`WORKBENCH_LLM_URL` to another OpenAI-compatible base URL and
`WORKBENCH_MODEL` to its model identifier. Set `WORKBENCH_LLM_KEY` only
when that endpoint requires authentication.

LM Studio runtime `llama.cpp@2.79.0` rejects Inkling 2 Mini's
`inkling2_loop` architecture. The local test used the same Q8_0 GGUF
from the LM Studio model directory with llama.cpp build b12600:

```sh
llama-server --model "$INKLING_GGUF" --alias inkling-2-mini \
  --host 127.0.0.1 --port 1236 --ctx-size 16384 --parallel 4 \
  --n-gpu-layers 99 --reasoning-budget 96
```

Set `WORKBENCH_LLM_URL=http://127.0.0.1:1236/v1` when starting the workbench
against that endpoint.

| Provider | Requirements |
| --- | --- |
| Local folder | Mix, Hex, Rebar, and Node 22 or later on PATH |
| Docker | A local engine with the images named in `lib/provider.ex` |
| Apple Container | A running `container system` on Apple silicon and the same images |
| Sprites | A test Sprite with Mix and Node, and a signed-in `sprite` CLI for localhost port forwarding. Set `SPRITES_TEST_TOKEN` to use the Elixir SDK for files and remote execution. |

The Phoenix recipe resolves dependencies from Hex on the selected provider.
The container cases mount only their project directory. Local runs use a
host process for trusted work. The Sprite cases use distinct directories under
`/home/sprite/.jido-workbench` and forward the live port to localhost. The
workbench holds the preview processes for review. Source files remain in the
run directories. The workbench keeps local builds and dependencies in the Realm
package's `tmp/coding-agent-workbench` directory.

The spike keeps provider launch code out of the Realm package API. The model
chooses source edits within each recipe's file list. The host fixes the
commands, image names, project roots, and ports.

The live matrix passed on all four providers. Each of the eight independent
projects returned HTTP 200 and showed “Hello, world!” in the browser. The
live Sprite runs used the signed-in CLI for files, commands, and port forwarding.
