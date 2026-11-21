defmodule Jido.Realm.FilePath do
  @moduledoc false

  @staging_prefix ".jido-realm-"

  def validate(path) when is_binary(path) do
    if String.valid?(path) and Path.type(path) == :relative and
         not String.contains?(path, <<0>>) and
         Enum.all?(String.split(path, "/"), &valid_component?/1) do
      :ok
    else
      {:error, :invalid_path}
    end
  end

  def validate(_), do: {:error, :invalid_path}

  def staging_name do
    @staging_prefix <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp valid_component?(component) do
    component not in ["", ".", ".."] and
      not String.starts_with?(String.downcase(component), @staging_prefix)
  end
end
