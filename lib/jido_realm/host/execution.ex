defmodule Jido.Realm.Host.Execution do
  @moduledoc "A completed command with bounded combined output and file observations."
  @enforce_keys [:id, :command, :status, :files, :after_files, :duration_ms]
  defstruct [
    :id,
    :command,
    :status,
    :exit_status,
    :files,
    :after_files,
    :duration_ms,
    output: "",
    truncated: false
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          command: String.t() | [String.t(), ...],
          status: :exited | :timed_out | :cancelled,
          exit_status: integer() | nil,
          files: Jido.Realm.Host.FileView.t() | nil,
          after_files: Jido.Realm.Host.FileView.t() | {:error, Jido.Realm.Host.Error.t()} | nil,
          duration_ms: non_neg_integer(),
          output: binary(),
          truncated: boolean()
        }
end
