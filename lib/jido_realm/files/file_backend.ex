defmodule Jido.Realm.FileBackend do
  @moduledoc false

  @type operation :: atom()

  @reasons [
    :already_exists,
    :not_found,
    :invalid_path,
    :not_a_file,
    :permission_denied,
    :conflict,
    :text_not_found,
    :ambiguous_match,
    :input_limit,
    :invalid_text,
    :unknown,
    :transfer_interrupted,
    :unsupported_file_operation,
    :backend_error
  ]

  defguard is_file_error(reason) when reason in @reasons

  @callback run(
              handle :: term(),
              operation(),
              relative_path :: String.t(),
              input :: term()
            ) ::
              :ok | {:ok, term()} | {:error, atom() | {:unknown, String.t()}}
end
