defmodule Jido.Realm.AppleEdit.Profile do
  @moduledoc false
  @behaviour Jido.Realm.Profile

  @impl true
  def requirements do
    %Jido.Realm.Profile{
      required: [:files, :tree, :revisions, :bash, :preview, :commands, :services, :ports],
      optional: [:background]
    }
  end
end

defmodule Jido.Realm.AppleEdit.EditAgent do
  @moduledoc false
  alias Jido.Realm.{AppleEdit, Coding}

  use Jido.AI.Agent, name: "realm_apple_edit_agent", plugins: [Jido.Realm.Plugin]

  realms do
    realm(:work, profile: AppleEdit.Profile)
  end

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      instructions("""
      You edit an existing small Elixir Phoenix project in a Jido Realm.
      Project source is in lib/realm_demo: page.ex has the home action, router.ex has the routes,
      and errors.ex renders Phoenix error pages. The existing app test is test/home_test.exs.
      Set realm to "work" in every tool call. Use read, edit, write and run_check.
      Run the named "project" check for Mix tests. For round 3 use "acceptance-3".
      Do not edit mix.exs, mix.lock, the acceptance tests, or app configuration.
      Read a file before changing it. Use the exact revision and exact old text from the read.
      Read newly created files too if you need to correct them after a test fails.
      Use the paths argument to batch independent reads. Wait for edits to finish before running tests.
      Preserve earlier behavior and keep changes small. Test the final version after all edits.
      Report the result briefly. Use tool calls for all edits and execution.
      """)

      limits do
        model_calls(16)
        tool_rounds(8)
        tool_calls(16)
        retries(0)
        elapsed_ms(220_000)
      end
    end

    tools do
      action(Coding.Glob)
      action(Coding.Grep)
      action(Coding.Read)
      action(Coding.Edit)
      action(Coding.Write)
      action(Coding.RunCheck)
    end
  end
end
