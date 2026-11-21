defmodule Jido.Realm.Host.Handle do
  @moduledoc "A stable handle for one Realm controller generation."
  @type t :: %__MODULE__{id: String.t(), lifetime: pid() | {:profile, {pid(), reference()}}}
  @enforce_keys [:id, :lifetime]
  defstruct [:id, :lifetime]
end
