# 03 Program execution

Turn file work into a program loop the agent can drive itself.

The default cases run Lua on Local and Memory. The Docker cases use the same
agent job for Bash, Python, and JavaScript. They verify that the program
loads an approved helper, receives literal arguments, reports an error,
and produces the expected report after repair.

```sh
mix test test/integration/03_program_execution
docker pull bash:5.2
docker pull python:3.13-alpine
docker pull node:22-alpine
mix test test/integration/03_program_execution --only docker
```

Set `JIDO_REALM_DOCKER_CONTEXT` to select a trusted context that can mount
local paths. You can select cached images with `JIDO_REALM_BASH_IMAGE`,
`JIDO_REALM_PYTHON_IMAGE`, and `JIDO_REALM_JAVASCRIPT_IMAGE`. The adapter
resolves the cached image ID when the Realm opens. Use a digest to pin
the host configuration across machines. Use a Linux image that declares
no Docker volumes.

Docker runs with a read-only root and input tree, a non-root user,
no network, and bounded scratch space, memory, processes, CPU, and
diagnostics. Realm removes the container before confirming a terminal
result. A worker survives session loss to attempt cleanup. If the BEAM
or daemon becomes unavailable before cleanup is confirmed, the host
can locate the container by the run ID or the `io.jido.realm.run=true`
label. A timeout limits the program, with separate bounded calls for
Docker setup and cleanup.
[Docker container options](https://docs.docker.com/reference/cli/docker/container/create/)

- [03.01 Write, run, and revise a program](03_01_write_run_and_revise/README.md)
- [03.02 Build and test with a toolchain](03_02_build_and_test_with_a_toolchain/README.md)
- [03.03 Publish staged output](03_03_publish_staged_output/README.md)
- [03.04 Observe a background run](03_04_observe_a_background_run/README.md)
- [03.05 Stop a run](03_05_stop_a_run/README.md)
- [03.06 Use an interactive run](03_06_use_an_interactive_run/README.md)
- [03.07 Invoke a host-approved command](03_07_invoke_a_host_approved_command/README.md)

[Integration ladder](../README.md)
