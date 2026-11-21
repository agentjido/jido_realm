defmodule Jido.Realm.Host.Examples.Report do
  @moduledoc "Write, copy, and read a report through one Workspace handle."

  alias Jido.Realm.Host

  def run(workspace, input) do
    with :ok <- Host.mkdir(workspace, "reports"),
         :ok <- Host.write(workspace, "reports/input data.txt", input),
         {:ok, %{exit_status: 0}} <-
           Host.run(workspace, ["cp", "input data.txt", "output data.txt"], cwd: "reports") do
      Host.read(workspace, "reports/output data.txt")
    else
      {:ok, %Host.Execution{} = execution} -> {:error, execution}
      error -> error
    end
  end
end
