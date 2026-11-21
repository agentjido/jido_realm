defmodule Jido.Realm.Host.Examples.ObserveCommand do
  @moduledoc "Forward command events for one workspace to the caller."

  alias Jido.Realm.Host

  @events [[:jido_realm, :command, :start], [:jido_realm, :command, :stop]]

  def attach(workspace) do
    handler = {__MODULE__, make_ref()}

    with {:ok, %{id: workspace_id}} <- Host.info(workspace),
         :ok <-
           :telemetry.attach_many(
             handler,
             @events,
             &__MODULE__.forward/4,
             {self(), workspace_id}
           ) do
      {:ok, handler}
    end
  end

  @doc false
  def forward(
        [:jido_realm, :command, event],
        measures,
        %{workspace_id: id} = data,
        {pid, id}
      ),
      do: send(pid, {:workspace_command, event, measures, data})

  def forward(_, _, _, _), do: :ok
end
