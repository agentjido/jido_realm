defmodule Jido.Realm.Commands do
  @moduledoc false

  alias Jido.Joi
  alias Jido.Realm.{FilePath, Files, Runner}

  def prepare(commands) when is_map(commands) do
    Map.filter(commands, fn
      {name, %{schema: schema, grant: grant, read: paths, run: handler}}
      when is_atom(name) and is_atom(grant) and is_list(paths) and is_function(handler, 2) ->
        Joi.validate_stored_schema(schema) == :ok and
          Enum.all?(paths, &(FilePath.validate(&1) == :ok))

      {name, %{schema: schema, grant: grant, exec: {kind, _, _}}}
      when is_atom(name) and is_atom(grant) and kind in [:entrypoint, :shell, :check] ->
        Joi.validate_stored_schema(schema) == :ok

      _ ->
        false
    end)
  end

  def prepare(_), do: %{}

  def available(commands, grants) do
    for {name, command} <- Enum.sort(commands), allowed?(command, grants) do
      %{name: name, schema: Joi.to_json_schema(command.schema)}
    end
  end

  defp allowed?(%{grant: grant, exec: _}, grants),
    do: Runner.allowed?(grants, :run) and Runner.allowed?(grants, grant)

  defp allowed?(%{grant: grant}, grants), do: Runner.allowed?(grants, grant)

  def request(commands, name, input, grants) do
    with {:ok, command} <- Map.fetch(commands, name),
         true <- allowed?(command, grants),
         :ok <- Joi.validate(command.schema, input) do
      {:ok, command}
    else
      :error -> {:error, :command_unavailable}
      false -> {:error, :permission_denied}
      {:error, _} -> {:error, :invalid_command_arguments}
    end
  end

  def run(command, input, binding) do
    command.run.(input, fn path ->
      if path in command.read,
        do: Files.execute(binding, :read, path, nil),
        else: {:error, :permission_denied}
    end)
  end
end
