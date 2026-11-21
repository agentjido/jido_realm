defmodule Jido.Realm.Host.Examples.RootedReport do
  alias Jido.Realm.Host

  def read_with_tool(workspace, path) do
    with {:ok, report} <- Host.read(workspace, path),
         file = "./" <> Path.basename(path),
         {:ok, execution} <-
           Host.run(workspace, ["cat", file], cwd: Path.dirname(path)) do
      {:ok, %{report: report, execution: execution}}
    end
  end
end
