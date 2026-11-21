defmodule Jido.Realm.CodingActionsTest do
  use ExUnit.Case, async: true, parameterize: [%{backend: :local}, %{backend: :memory}]

  alias Jido.Realm.{Coding, Local, Memory, Plugin}

  setup %{backend: backend} do
    target =
      case backend do
        :local ->
          root =
            Path.join(System.tmp_dir!(), "coding-actions-#{System.unique_integer([:positive])}")

          File.mkdir!(root)
          on_exit(fn -> File.rm_rf!(root) end)
          {Local, root}

        :memory ->
          {Memory, start_supervised!(Memory)}
      end

    {module, handle} = target
    assert :ok = module.run(handle, :mkdir, "lib", nil)

    context = fn grants ->
      %{plugin_inputs: %{Plugin => %{runtime: %{binding: %{target: target, grants: grants}}}}}
    end

    %{context: context, observe: &module.run(handle, :read, &1, nil)}
  end

  test "confirms mutations, rejects stale or ambiguous edits, and bounds discovery", ctx do
    context = ctx.context.(:all)
    path = "lib/demo.ex"

    assert {:ok, %{revision: first}} =
             call(Coding.Write, context, %{path: path, content: "first\nrepeat\nrepeat\n"})

    assert {:error, _} =
             call(Coding.Write, context, %{path: path, content: "replace without a revision"})

    assert {:ok, %{files: [file, %{path: "../skip", error: :invalid_path}]}} =
             call(Coding.Read, context, %{paths: [path, "../skip"], start_line: 2, line_count: 1})

    assert %{path: ^path, content: "repeat", revision: ^first, truncated: true, start_line: 2} =
             file

    params = %{path: path, revision: first, old_text: "repeat", new_text: "changed"}
    assert {:error, %{message: ambiguous}} = call(Coding.Edit, context, params)
    assert ambiguous =~ "ambiguous_match"

    assert {:error, %{message: missing}} =
             call(Coding.Edit, context, %{params | old_text: "absent"})

    assert missing =~ "text_not_found"

    assert {:ok, %{revision: committed}} =
             call(Coding.Edit, context, %{params | old_text: "first"})

    assert committed != first
    assert {:ok, "changed\nrepeat\nrepeat\n"} = ctx.observe.(path)

    assert {:error, %{message: stale}} =
             call(Coding.Edit, context, %{params | old_text: "changed"})

    assert stale =~ "conflict"

    assert {:ok, %{paths: [^path], truncated: false}} =
             call(Coding.Glob, context, %{pattern: "**/*.ex"})

    assert {:ok, %{matches: [%{path: ^path, line: 2, text: "repeat"}], truncated: true}} =
             call(Coding.Grep, context, %{query: "repeat", limit: 1})

    assert {:error, _} =
             call(Coding.Grep, context, %{query: "rep.*", regex: true})

    assert {:error, _} =
             call(Coding.Edit, ctx.context.([:read]), %{params | revision: committed})
  end

  test "a denied read cannot be recovered with file discovery", ctx do
    for {tool, input} <- [
          {Coding.Read, %{path: "unknown.txt"}},
          {Coding.Glob, %{pattern: "**/*"}},
          {Coding.Grep, %{query: "secret"}}
        ] do
      assert {:error, %{message: message}} = call(tool, ctx.context.([:write]), input)
      assert message =~ "permission_denied"
    end
  end

  defp call(action, context, params), do: Jido.Exec.run(action, params, context)
end
