defmodule Jido.Realm.Host.Examples.ProfiledReport do
  @moduledoc "Run the same report with a host-selected provider profile."

  alias Jido.Realm.Host
  alias Jido.Realm.Host.Examples.Report

  def run(profile, input) do
    with {:ok, workspace} <- Host.open(profile: profile) do
      try do
        Report.run(workspace, input)
      after
        Host.close(workspace)
      end
    end
  end
end
