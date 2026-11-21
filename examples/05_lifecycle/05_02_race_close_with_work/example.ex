defmodule Jido.Realm.Host.Examples.FinishWork do
  @moduledoc "Close a workspace while keeping the last known snapshot available."

  alias Jido.Realm.Host
  alias Jido.Realm.Host.Error

  def close(workspace, last_saved, timeout_ms) do
    case Host.close(workspace, timeout_ms: timeout_ms) do
      :ok ->
        {:closed, last_saved}

      {:error, %Error{code: :cleanup_unconfirmed}} ->
        {:cleanup_unconfirmed, workspace, last_saved}

      {:error, _} = error ->
        error
    end
  end
end
