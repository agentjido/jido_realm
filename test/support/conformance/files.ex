defmodule Jido.Realm.Conformance.Files do
  @moduledoc """
  Runs the same file exercises through a live agent for each binding.
  """

  import ExUnit.Assertions

  alias Jido.Realm.Plugin

  defmodule FileAgent do
    @moduledoc false
    use Jido.Agent, name: "realm_file_agent", plugins: [Plugin]
  end

  defmacro __using__(opts) do
    parameters =
      for {name, fixture} <- Keyword.fetch!(opts, :bindings) do
        quote do: %{binding: unquote(name), fixture: unquote(fixture)}
      end

    quote do
      use ExUnit.Case, parameterize: unquote(parameters)

      alias Jido.Realm.Conformance.Files

      @moduletag :realm_file_contract

      setup %{fixture: fixture} = context do
        %{runtime_options: options, observe: observe} = fixture.prepare(context)
        %{server: Files.start_agent(__MODULE__, options), observe: observe}
      end

      test "creates, reads, edits, and deletes a file", %{server: server, observe: observe} do
        path = "notes.txt"
        edited = "Edited café\n"

        assert {:ok, %{status: :committed, reply: %{type: "realm.file.result", data: data}}} =
                 Files.call(server, :create, %{"path" => path, "content" => ""})

        assert data == %{operation: :create, path: path}
        assert observe.(path) == {:ok, ""}
        Files.assert_reply(server, :read, path, %{}, %{content: ""})

        Files.assert_reply(server, :edit, path, %{content: edited})
        assert observe.(path) == {:ok, edited}
        Files.assert_reply(server, :read, path, %{}, %{content: edited})

        Files.assert_reply(server, :delete, path)
        assert observe.(path) == {:error, :not_found}
        Files.assert_rejected(server, :read, path, :not_found)
      end

      test "rejects a duplicate create and preserves the original bytes", %{
        server: server,
        observe: observe
      } do
        path = "notes.txt"
        Files.assert_reply(server, :create, path, %{content: "original"})
        Files.assert_rejected(server, :create, path, :already_exists, %{content: "duplicate"})

        Files.assert_rejected(server, :create, "notes.txt/child.txt", :not_a_file, %{
          content: "nested"
        })

        assert observe.(path) == {:ok, "original"}
      end

      test "rejects reads, edits, and deletes of a missing file", %{
        server: server,
        observe: observe
      } do
        path = "missing.txt"
        Files.assert_rejected(server, :read, path, :not_found)
        Files.assert_rejected(server, :edit, path, :not_found, %{content: "edited"})
        Files.assert_rejected(server, :delete, path, :not_found)
        Files.assert_rejected(server, :create, "missing/notes.txt", :not_found, %{content: "new"})
        assert observe.(path) == {:error, :not_found}
      end

      test "rejects absolute paths, parent components, and reserved names", %{server: server} do
        Files.assert_rejected(server, :read, "/notes.txt", :invalid_path)
        Files.assert_rejected(server, :delete, "../notes.txt", :invalid_path)
        Files.assert_rejected(server, :read, ".jido-realm-staged", :invalid_path)
      end

      test "requires text on create and edit", %{server: server, observe: observe} do
        path = "notes.txt"
        Files.assert_rejected(server, :create, path, :content_required)
        assert observe.(path) == {:error, :not_found}
        Files.assert_reply(server, :create, path, %{content: "original"})
        Files.assert_rejected(server, :edit, path, :content_required)
        assert observe.(path) == {:ok, "original"}
      end

      test "keeps agents bound to their own store",
           %{fixture: fixture, server: server, observe: observe} = context do
        %{runtime_options: options, observe: observe_other} = fixture.prepare(context)
        other = Files.start_agent(__MODULE__, "other-files", options)
        path = "notes.txt"

        Files.assert_reply(other, :create, path, %{content: "other agent"})
        Files.assert_rejected(server, :read, path, :not_found)
        Files.assert_rejected(server, :edit, path, :not_found, %{content: "changed"})
        Files.assert_reply(server, :create, path, %{content: "first agent"})

        Files.assert_reply(server, :read, path, %{}, %{content: "first agent"})
        Files.assert_reply(other, :read, path, %{}, %{content: "other agent"})
        assert observe.(path) == {:ok, "first agent"}
        assert observe_other.(path) == {:ok, "other agent"}
      end

      test "rejects host binding options in file Signals", %{server: server, observe: observe} do
        path = "notes.txt"

        for option <- [:root, :backend] do
          input = Map.put(%{path: path, content: "write"}, option, "another binding")
          assert {:ok, %{status: :failed, reply: nil}} = Files.call(server, :create, input)
          assert observe.(path) == {:error, :not_found}
        end

        Files.assert_reply(server, :create, path, %{content: "write"})
        assert observe.(path) == {:ok, "write"}
      end
    end
  end

  def start_agent(instance, options) do
    ExUnit.Callbacks.start_supervised!({Jido, name: instance})
    start_agent(instance, "files", options)
  end

  def start_agent(instance, id, options) do
    Jido.Realm.Conformance.Scenarios.start_agent(instance, FileAgent, id, options)
  end

  def call(server, operation, data) do
    signal = Jido.Signal.new!("realm.file.#{operation}", data, source: "/test")
    Jido.AgentServer.call(server, signal)
  end

  def assert_reply(server, operation, path, data \\ %{}, result \\ %{}) do
    assert {:ok, %{status: :committed, reply: %{type: "realm.file.result", data: reply}}} =
             call(server, operation, Map.put(data, :path, path))

    assert reply == Map.merge(%{operation: operation, path: path}, result)
  end

  def assert_rejected(server, operation, path, reason, data \\ %{}) do
    assert {:ok,
            %{
              status: :failed,
              reply: nil,
              error: %{
                details: %{
                  code: :realm_file_error,
                  operation: ^operation,
                  path: ^path,
                  reason: ^reason
                }
              }
            }} = call(server, operation, Map.put(data, :path, path))
  end
end
