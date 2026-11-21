defmodule Jido.Realm.Host.ActionSignalBoundaryTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag capture_log: true

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Deploy, Sandbox}
  alias Jido.Realm.Host.Deploy.{Artifact, Snapshot}
  alias Jido.Realm.Host.TestSupport.{ActionBoundary, Actions, BoundaryAgent}

  setup do
    assert {:ok, _} = Application.ensure_all_started(:jido)
    start_supervised!({Jido, name: __MODULE__.Runtime})
    store = start_supervised!({Agent, fn -> %{} end})
    {:ok, ws} = Host.open()
    {:ok, restricted} = Host.open(policy: :read_only)
    {:ok, sandbox} = Sandbox.open()

    on_exit(fn ->
      Host.close(ws)
      Host.close(restricted)
      Sandbox.destroy(sandbox)
    end)

    {:ok, target} = Deploy.source_target(sandbox, "site")
    {:ok, deployment} = Deploy.connect(target)

    access = %{
      store: store,
      reply_to: self(),
      resources: %{
        "draft" => {:workspace, ws},
        "readonly" => {:workspace, restricted},
        "execution" => {:sandbox, sandbox},
        "site" => {:deployment, deployment}
      }
    }

    {:ok, agent} =
      Jido.start_agent(__MODULE__.Runtime, BoundaryAgent,
        id: "workspace-#{System.unique_integer([:positive, :monotonic])}",
        exec_opts: [max_attempts: 1]
      )

    %{
      access: access,
      ws: ws,
      restricted: restricted,
      sandbox: sandbox,
      deployment: deployment,
      agent: agent
    }
  end

  test "Actions and Agent Signals share real files, captures, and checked replacement", ctx do
    params = %{request_id: "direct-write", resource_id: "draft", path: "/input", content: "first"}

    assert {:ok, %{request_id: "direct-write", result: %{path: "/input"}}} =
             Jido.Exec.run(Actions.Write, params, %{workspace_access: ctx.access},
               max_attempts: 1
             )

    assert {:ok, "first"} = Host.read(ctx.ws, "/input")

    assert %{result: %{content: "first"}} =
             request(ctx, "read", %{path: "/input"})

    {:ok, view} = Host.file_view(ctx.ws)
    view_ref = ActionBoundary.put(ctx.access.store, "draft", :file_view, view)

    assert %{result: %{output: "first", checked_files: true}} =
             request(ctx, "run", %{command: "cat /input", file_view_ref: view_ref})

    saved = request(ctx, "capture", %{}).result
    request(ctx, "write", %{path: "/input", content: "second"})

    assert %{error: %{code: "stale_file_view"}} =
             request(
               ctx,
               "run",
               %{command: "write /marker bad", file_view_ref: view_ref},
               "draft",
               "failed"
             )

    assert {:error, %Jido.Realm.Host.Error{code: :not_found}} = Host.read(ctx.ws, "/marker")

    assert %{error: %{code: "stale_revision"}} =
             request(ctx, "replace", saved, "draft", "failed")

    assert {:ok, "second"} = Host.read(ctx.ws, "/input")
    current = request(ctx, "capture", %{}).result

    assert %{result: %{revision_ref: _}} =
             request(ctx, "replace", %{saved | revision_ref: current.revision_ref})

    assert {:ok, "first"} = Host.read(ctx.ws, "/input")
    {:ok, capture} = ActionBoundary.fetch(ctx.access.store, "draft", :capture, saved.capture_ref)
    :ok = Host.close(ctx.ws)
    assert {:ok, "first"} = Jido.VFS.read(capture, "input")
    refute_receive {:signal, _}
  end

  test "policy, resource access, and Action schemas refuse changes", ctx do
    assert %{error: %{code: "policy_denied", operation: "write"}} =
             request(
               ctx,
               "write",
               %{path: "/blocked", content: "bad"},
               "readonly",
               "failed"
             )

    assert {:error, %Jido.Realm.Host.Error{code: :not_found}} =
             Host.read(ctx.restricted, "/blocked")

    assert %{error: %{code: "resource_not_found"}} =
             request(
               ctx,
               "write",
               %{path: "/blocked", content: "bad"},
               "unknown",
               "failed"
             )

    assert {:error, _} =
             Jido.Exec.run(
               Actions.Write,
               %{request_id: "invalid", resource_id: "draft", path: "/blocked", content: 42},
               %{workspace_access: ctx.access},
               max_attempts: 1
             )

    assert {:error, %Jido.Realm.Host.Error{code: :not_found}} = Host.read(ctx.ws, "/blocked")

    saved = request(ctx, "capture", %{}).result

    assert %{error: %{code: "resource_not_found"}} =
             request(ctx, "replace", saved, "readonly", "failed")

    refute_receive {:signal, _}
  end

  test "Agent Signals run a local command and deploy the captured workspace bytes", ctx do
    request(ctx, "write", %{path: "/index.txt", content: "accepted bytes"})
    {:ok, bytes} = Host.read(ctx.ws, "/index.txt")
    :ok = Sandbox.write(ctx.sandbox, "input.txt", bytes)

    assert %{result: %{output: "accepted bytes", exit_status: 0}} =
             request(
               ctx,
               "sandbox.exec",
               %{executable: "/bin/cat", args: ["input.txt"]},
               "execution"
             )

    assert %{result: %{exit_status: 7}} =
             request(
               ctx,
               "sandbox.exec",
               %{executable: "/bin/sh", args: ["-c", "exit 7"]},
               "execution"
             )

    {:ok, snapshot} = Snapshot.new(%{"index.txt" => %{bytes: bytes, mode: 0o644}}, id: "source-1")
    {:ok, artifact} = Artifact.new(:source, "1", snapshot)
    artifact_ref = ActionBoundary.put(ctx.access.store, "site", :artifact, artifact)

    prepared = request(ctx, "deploy.prepare", %{artifact_ref: artifact_ref}, "site").result
    assert {:ok, %{identity: %{current: nil}}} = Deploy.inspect(ctx.deployment)
    refute File.exists?(Path.join(ctx.sandbox.root, "site/current"))

    applied = request(ctx, "deploy.apply", prepared, "site").result
    assert %{result: ^applied} = request(ctx, "deploy.apply", prepared, "site")

    assert %{
             result: %{
               status: "succeeded",
               source_id: "source-1",
               digest: digest,
               step_count: steps,
               state_policy: "files_only"
             }
           } =
             request(ctx, "deploy.await", applied, "site")

    assert digest == snapshot.digest
    assert steps > 0
    assert File.read!(Path.join(ctx.sandbox.root, "site/current/index.txt")) == bytes

    assert :ok = Sandbox.destroy(ctx.sandbox)
    refute File.exists?(ctx.sandbox.root)
    refute Process.alive?(ctx.deployment)
  end

  defp request(ctx, operation, data, resource_id \\ "draft", outcome \\ "succeeded") do
    request_id = "request-#{System.unique_integer([:positive, :monotonic])}"
    prefix = "realm.host.v1." <> operation

    signal =
      Jido.Signal.new!(
        prefix <> ".requested",
        Map.merge(data, %{request_id: request_id, resource_id: resource_id}),
        source: "/workspace/integration-test"
      )

    # An Agent acknowledgement does not prove that the requested operation succeeded.
    assert {:ok, turn} =
             Jido.AgentServer.call(ctx.agent, signal,
               timeout: 15_000,
               context: %{workspace_access: ctx.access}
             )

    expected_status = if outcome == "succeeded", do: :committed, else: :failed
    assert %Jido.AgentServer.TurnResult{status: ^expected_status} = turn

    expected_type = prefix <> "." <> outcome
    causation_id = signal.id

    assert_receive {:signal,
                    %Jido.Signal{
                      type: ^expected_type,
                      data:
                        %{
                          request_id: ^request_id,
                          resource_id: ^resource_id,
                          causation_id: ^causation_id
                        } = reply
                    }},
                   15_000

    assert {:ok, _} = Jason.encode(reply)
    reply
  end
end
