defmodule Jido.Realm.Host.Examples.OwnedReport do
  @moduledoc "Place a workspace under a host-owned process and save a recovery point."

  alias Jido.Realm.Host

  def prepare(profile, owner, report) do
    with {:ok, workspace} <- Host.open(profile: profile, owner: owner) do
      case save_report(workspace, report) do
        {:ok, snapshot} ->
          {:ok, workspace, snapshot}

        {:error, _} = error ->
          with :ok <- Host.close(workspace), do: error
      end
    end
  end

  defp save_report(workspace, report) do
    with :ok <- Host.write(workspace, "report.txt", report), do: Host.save(workspace)
  end
end
