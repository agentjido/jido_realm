defmodule Jido.Realm.Host.PolicyTest do
  use ExUnit.Case, async: false
  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Deploy, Policy, Sandbox}
  alias Jido.Realm.Host.Deploy.{Artifact, Snapshot, Target}

  test "profiles refuse unknown permissions and profiles" do
    assert {:error, :invalid_policy} = Policy.validate(:unknown)
    assert {:error, {:policy_denied, :unknown}} = Policy.authorize(:full_access, :unknown)

    assert {:error, %Jido.Realm.Host.Error{code: :invalid_input}} =
             Host.open(policy: :unknown)

    assert {:error, :invalid_policy} = Sandbox.open(policy: :unknown)
  end

  test "read only workspace permits capture and blocks mutation and shell handles" do
    {:ok, workspace} = Host.open(policy: :read_only)
    on_exit(fn -> Host.close(workspace) end)
    assert {:ok, capture, token} = Host.capture(workspace)
    assert {:ok, []} = Host.list(workspace)

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied}} =
             Host.write(workspace, "/a", "a")

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied}} =
             Host.mkdir(workspace, "/dir")

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied}} =
             Host.delete(workspace, "/a")

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied}} =
             Host.replace(workspace, capture, expected: token)

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied}} = Host.filesystem(workspace)

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied, operation: :shell}} =
             Host.shell(workspace)

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied}} =
             Host.run(workspace, "echo blocked")
  end

  test "workspace write permits files and keeps execution closed" do
    {:ok, workspace} = Host.open(policy: :workspace_write)
    on_exit(fn -> Host.close(workspace) end)
    assert :ok = Host.write(workspace, "/a", "a")
    assert {:ok, "a"} = Host.read(workspace, "/a")
    assert {:ok, saved, token} = Host.capture(workspace)
    assert {:ok, _} = Host.replace(workspace, saved, expected: token)

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied}} =
             Host.start_session(workspace)

    assert {:error, %Jido.Realm.Host.Error{code: :policy_denied}} = Host.filesystem(workspace)
  end

  test "environment policy is authoritative for attached and modified handles" do
    {:ok, environment} = Sandbox.open(policy: :read_only)
    on_exit(fn -> Sandbox.destroy(environment) end)
    {:ok, attached} = Sandbox.attach(environment.id)
    fake_root = Path.join(System.tmp_dir!(), "policy-#{System.unique_integer([:positive])}")

    assert {:error, {:policy_denied, :write}} =
             Sandbox.write(%{attached | root: fake_root}, "a", "a")

    refute File.exists?(fake_root)
    assert {:error, {:policy_denied, :execute}} = Sandbox.exec(attached, "touch", ["a"])

    assert {:error, {:policy_denied, :execute}} =
             Sandbox.start_service(attached, %{kind: :beam})

    assert {:error, {:policy_denied, :deploy}} = Deploy.source_target(attached, "app")
    {:ok, snapshot} = Snapshot.new(%{"a" => %{bytes: "a", mode: 0o644}})
    assert {:error, {:policy_denied, :write}} = Snapshot.project(snapshot, attached, "release")
    refute File.exists?(Path.join(environment.root, "release"))
  end

  test "deployment checks policy before it starts an operation" do
    {:ok, environment} = Sandbox.open(policy: :workspace_write)
    on_exit(fn -> Sandbox.destroy(environment) end)
    target = %Target{name: "app", sandbox: environment, kind: :source, path: "app"}
    {:ok, session} = Deploy.connect(target)
    {:ok, snapshot} = Snapshot.new(%{"a" => %{bytes: "a", mode: 0o644}})
    {:ok, artifact} = Artifact.new(:source, "1", snapshot)
    {:ok, plan} = Deploy.prepare(session, artifact)
    assert {:error, {:policy_denied, :deploy}} = Deploy.apply(session, plan)
    assert {:error, :operation_not_found} = Deploy.status(session, plan.id)
    refute File.exists?(Path.join(environment.root, "app"))
  end
end
