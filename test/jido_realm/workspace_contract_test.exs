defmodule Jido.Realm.WorkspaceContractTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Context.Admission
  alias Jido.Realm
  alias Jido.Realm.{Artifacts, Files, Local, Memory, Plugin, WorkspaceAction}

  test "file-only bindings reject managed operations and can still run file actions" do
    context = context(%{bindings: %{"work" => %{target: {Memory, nil}, grants: :all}}})
    assert {:error, :managed_session_required} = Realm.open(context, :work)
    assert {:error, :managed_session_required} = Realm.run(context, :work, :lua, "run.lua")
    assert {:error, :managed_session_required} = Realm.start_run(context, :work, :lua, "run.lua")
    assert {:error, :managed_session_required} = Realm.run_status(context, :work, "id")

    assert {:error, :managed_session_required} =
             Realm.start_preview(context, :work, :python, "run.py")

    assert {:error, :invalid_run_options} =
             Realm.start_preview(context, :work, :python, "run.py", outputs: ["out.txt"])

    assert {:error, :managed_session_required} = Realm.stop_preview(context, :work, "id")
    assert {:error, :managed_session_required} = Realm.share_preview(context, :work, "id", 300)
    assert {:error, :managed_session_required} = Realm.commands(context, :work)
    assert {:error, :managed_session_required} = Realm.invoke(context, :work, "build", %{})

    assert {:error, :artifact_presenter_unavailable} =
             Realm.publish_artifact(context, :work, "index.html", ["index.html"])

    assert {:error, :realm_name_required} = Realm.file(context, nil, :read, "note")
    assert {:error, :unknown_realm} = Realm.file(context, 123, :read, "note")
    assert {:error, :live_realm_required} = Realm.open(%{}, :work)
    assert {:error, :live_realm_required} = WorkspaceAction.run(%{}, %{})
  end

  test "admission refuses missing bindings, conflicting backends and invalid presenters" do
    unnamed = %Admission{
      plugin: Plugin,
      agent_id: "test",
      agent_module: __MODULE__,
      caller_context: %{},
      plugin_state: %{},
      state_version: 0,
      prepared_input: [],
      signal: %{type: "realm.file.read"}
    }

    assert {:ok, nil} =
             Plugin.admit(nil, %{unnamed | signal: %{type: "something.else"}}, [])

    assert {:error, :realm_root_required} = Plugin.admit(nil, unnamed, [])

    assert {:error, :conflicting_realm_options} =
             Plugin.admit(nil, unnamed, root: "/example", backend: {Memory, self()})

    assert {:error, :invalid_realm_backend} = Plugin.admit(nil, unnamed, root: 123)

    named = %{unnamed | prepared_input: [%{name: :work, profile: :files}]}

    assert {:error, {:realm_binding_required, :work}} =
             Plugin.admit(nil, named, bindings: %{wrong: [root: "/example"]})

    assert {:error, {:invalid_realm_binding, :work, :invalid_artifact_presenter}} =
             Plugin.admit(nil, named, bindings: %{work: [root: "/example", presenter: true]})
  end

  @tag :tmp_dir
  test "replace streams create or overwrite regular files in both locations", %{tmp_dir: dir} do
    memory = start_supervised!(Memory)

    for binding <- [{Memory, memory}, {Local, dir}] do
      assert {:ok, _} = Files.execute(binding, :write_stream, "new", {["hel", "lo"], true})
      assert {:ok, %{content: "hello"}} = Files.execute(binding, :read, "new", nil)
      assert {:ok, _} = Files.execute(binding, :write_stream, "new", {["updated"], true})
      assert {:ok, %{content: "updated"}} = Files.execute(binding, :read, "new", nil)
      assert {:ok, _} = Files.execute(binding, :mkdir, "directory", nil)

      assert {:error, :not_a_file} =
               Files.execute(binding, :write_stream, "directory", {["data"], true})

      assert {:error, :not_a_file} = Files.execute(binding, :read, "new/child/grandchild", nil)
    end

    assert {:error, :unsupported_file_operation} = Memory.run(memory, :unsupported, "new", nil)
  end

  test "the artifact store validates direct host requests before using its capacity" do
    store = start_supervised!({Artifacts, viewers: [:reviewer], max_artifacts: 1})

    for {entry, files} <- [
          {nil, %{nil => "<h1>Bad name</h1>"}},
          {"index.html", %{}},
          {"index.html", ["index.html"]},
          {"index.html", %{"index.html" => <<255>>}}
        ] do
      assert {:error, :invalid_artifact_bundle} = Artifacts.publish(store, entry, files)
    end

    assert {:ok, artifact} = Artifacts.publish(store, "index.html", %{"index.html" => "Hello"})
    assert {:ok, %{content: "Hello"}} = Artifacts.read(store, :reviewer, artifact.id)
  end

  defp context(runtime), do: %{plugin_inputs: %{Plugin => %{runtime: runtime}}}
end
