defmodule Jido.Realm.Host.Examples.PublishReport do
  alias Jido.Realm.Host

  def publish(workspace, path) do
    with {:ok, report} <- Host.read(workspace, path),
         {:ok, snapshot} <- Host.save(workspace) do
      {:ok, %{report: report, snapshot: snapshot}}
    end
  end
end
