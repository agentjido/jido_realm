defmodule Jido.Realm.Host.Examples.RestrictedReport do
  @moduledoc "Observe which operations a read-only Workspace permits."

  alias Jido.Realm.Host

  def check(workspace) do
    %{
      read: Host.read(workspace, "report.txt"),
      write: Host.write(workspace, "report.txt", "Changed"),
      run: Host.run(workspace, ["cat", "report.txt"])
    }
  end
end
