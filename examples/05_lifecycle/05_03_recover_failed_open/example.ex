defmodule Jido.Realm.Host.Examples.ReopenReport do
  @moduledoc "Use a saved report to retry an open after the allocation wait expires."

  alias Jido.Realm.Host
  alias Jido.Realm.Host.Error

  def reopen(profile, snapshot, timeout_ms) do
    case Host.open(profile: profile, from: snapshot, timeout_ms: timeout_ms) do
      {:error, %Error{code: :open_timeout} = error} ->
        {:retry_open, snapshot, error}

      result ->
        result
    end
  end
end
