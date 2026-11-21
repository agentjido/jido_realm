defmodule Jido.Realm.Host.Examples.AppleContainer do
  @moduledoc "Copy a report with literal arguments and save the workspace tree."

  alias Jido.Realm.Host

  def copy_and_save(workspace, report) do
    directory = "reports today"
    source = "draft $notes.txt"
    destination = "reviewed report.txt"

    with :ok <- Host.mkdir(workspace, directory),
         :ok <- Host.write(workspace, Path.join(directory, source), report),
         {:ok, %{status: :exited, exit_status: 0}} <-
           Host.run(workspace, ["/bin/cp", source, destination], cwd: directory) do
      Host.save(workspace)
    else
      {:ok, execution} -> {:error, execution}
      {:error, _} = error -> error
    end
  end
end
