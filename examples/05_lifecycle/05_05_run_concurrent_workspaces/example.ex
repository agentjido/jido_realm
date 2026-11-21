defmodule Jido.Realm.Host.Examples.ConcurrentReports do
  @moduledoc "Read a report in a caller task while the host retains workspace ownership."

  alias Jido.Realm.Host

  def read(workspace, opts \\ []) do
    Task.async(fn -> Host.run(workspace, ["cat", "report.txt"], opts) end)
  end
end
