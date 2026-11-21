defmodule Jido.Realm.Provider do
  @moduledoc """
  Allocates or attaches a placement and releases the same lease on close.

  A provider can supply `:runners` with the lease. The host can also
  configure or replace runners when starting the Session.
  """

  @type lease :: %{
          required(:binding) => {module(), term()},
          required(:capabilities) => map(),
          required(:placement) => term(),
          optional(:ownership) => :borrowed | :owned,
          optional(:runners) => %{atom() => {module(), term()}}
        }

  @callback open(options :: term()) :: {:ok, lease()} | {:error, term()}
  @callback close(lease(), options :: term()) :: :ok | {:error, :unknown | term()}
  @callback save(lease(), verified_tree :: String.t() | nil) :: {:ok, map()} | {:error, term()}
  @optional_callbacks save: 2
end
