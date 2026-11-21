defmodule Jido.Realm.Host.Examples.DisposableSandbox do
  @moduledoc "Copy a report inside a disposable workspace."

  alias Jido.Realm.Host

  def copy_report(workspace, report) do
    with :ok <- Host.write(workspace, "input.txt", report),
         {:ok, %{status: :exited, exit_status: 0}} <-
           Host.run(workspace, ["/bin/cp", "input.txt", "report.txt"]) do
      Host.save(workspace)
    else
      {:ok, execution} -> {:error, execution}
      {:error, _} = error -> error
    end
  end
end
