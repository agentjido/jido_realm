defmodule Jido.Realm.Host.Examples.PersistedReport do
  @moduledoc "Save a report and reopen its tree from a reference stored as JSON."

  alias Jido.Realm.Host

  def export(profile, report, reference_path) do
    with {:ok, workspace} <- Host.open(profile: profile) do
      try do
        with :ok <- Host.mkdir(workspace, "empty"),
             :ok <- Host.write(workspace, "report.txt", report),
             {:ok, snapshot} <- Host.save(workspace),
             {:ok, json} <- Jason.encode(snapshot),
             :ok <- File.write(reference_path, json) do
          {:ok, snapshot}
        end
      after
        Host.close(workspace)
      end
    end
  end

  def restore(profile, reference_path) do
    with {:ok, json} <- File.read(reference_path),
         {:ok, snapshot} <- Jason.decode(json),
         {:ok, workspace} <- Host.open(profile: profile, from: snapshot) do
      try do
        with {:ok, report} <- Host.read(workspace, "report.txt"),
             {:ok, empty_entries} <- Host.list(workspace, "empty") do
          {:ok, %{report: report, empty_entries: empty_entries}}
        end
      after
        Host.close(workspace)
      end
    end
  end
end
