defmodule Jido.Realm.Host.Examples.StopCommand do
  @moduledoc "Request a stop and wait only as long as the caller can wait."

  alias Jido.Realm.Host

  def cancel_and_wait(workspace, execution_id, task, wait_ms) do
    with :ok <- Host.cancel(workspace, execution_id) do
      case Task.yield(task, wait_ms) do
        {:ok, result} -> result
        nil -> {:pending, task}
        {:exit, _} = exit -> exit
      end
    end
  end
end
