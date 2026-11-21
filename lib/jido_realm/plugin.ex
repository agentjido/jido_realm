defmodule Jido.Realm.Plugin do
  @moduledoc """
  Adds Realm lifecycle, file, program, and artifact operations to a live Jido agent.

  Declare a named Realm in the agent:

      realms do
        realm :work, profile: :files
      end

  Supply `bindings: %{work: [root: directory]}` in `plugin_runtime_options`
  when starting the agent. For an agent with a single unnamed Realm, supply
  `root: directory` or `backend: {module, handle}` directly.
  """

  alias Jido.Agent.Schema
  alias Jido.Plugin.Context.Admission
  alias Jido.Realm.{FileAction, Local, Profile, RunAction, WorkspaceAction}

  defmodule Declaration do
    @moduledoc false
    defstruct [:name, :profile, :__spark_metadata__]
  end

  @realm %Spark.Dsl.Entity{
    name: :realm,
    target: Declaration,
    args: [:name],
    modules: [:profile],
    schema: [
      name: [type: :atom, required: true],
      profile: [type: :atom, required: true]
    ]
  }
  @realms %Spark.Dsl.Section{name: :realms, entities: [@realm]}

  use Jido.Plugin,
    id: "jido.realm",
    sections: [@realms],
    option_keys: [agent: [:realms], agent_server: [:root, :backend, :bindings]]

  @operations %{
    "realm.file.create" => :create,
    "realm.file.read" => :read,
    "realm.file.edit" => :edit,
    "realm.file.delete" => :delete,
    "realm.file.mkdir" => :mkdir,
    "realm.file.list" => :list,
    "realm.file.rename" => :rename,
    "realm.file.read_revision" => :read_revision,
    "realm.file.edit_revision" => :edit_revision,
    "realm.file.delete_revision" => :delete_revision,
    "realm.file.reconcile" => :reconcile,
    "realm.file.search" => :search
  }
  @workspace_operations %{
    "realm.open" => :open,
    "realm.close" => :close,
    "realm.artifact.publish" => :publish
  }
  @signals Map.merge(@operations, @workspace_operations)

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    case {Spark.Dsl.Extension.get_entities(dsl, [:realms]), config} do
      {[], config} ->
        {:ok, config}

      {realms, config} when map_size(config) == 0 ->
        {:ok, %{realms: Enum.map(realms, &Map.take(&1, [:name, :profile]))}}

      _ ->
        {:error, :conflicting_realm_declarations}
    end
  end

  @impl Jido.Agent.Extension
  def normalize(config) when map_size(config) == 0, do: {:ok, config}

  def normalize(config) do
    with {:ok, %{realms: realms}} <- Schema.fields(config, [:realms]),
         {:ok, realms} <- Schema.list(realms, &normalize_realm/1),
         :ok <- Schema.unique(realms, & &1.name) do
      {:ok, %{realms: realms}}
    end
  end

  defp normalize_realm(realm) do
    with {:ok, %{name: name, profile: profile} = realm} <- Schema.fields(realm, [:name, :profile]),
         :ok <- Schema.name(name),
         :ok <- Schema.name(profile) do
      {:ok, realm}
    else
      {:ok, _realm} -> {:error, :unsupported_realm_profile}
      {:error, _} = error -> error
    end
  end

  @impl Jido.Agent.Extension
  def derive_routes(_data) do
    operations =
      for {signals, action} <- [
            {@operations, FileAction},
            {@workspace_operations, WorkspaceAction}
          ],
          {type, _operation} <- signals do
        %{path: type, handler: %{kind: :action, target: action}, state: :unchanged}
      end

    [
      %{
        path: "realm.program.run",
        handler: %{kind: :action, target: RunAction},
        state: :unchanged
      }
      | operations
    ]
  end

  @impl Jido.Plugin
  def prepare(_context, opts), do: {:ok, Keyword.get(opts, :realms, [])}

  @impl Jido.Plugin
  def admit(_runtime, %Admission{prepared_input: [], signal: %{type: type}}, opts)
      when is_map_key(@operations, type) do
    with {:ok, binding} <- bind_backend(opts) do
      {:ok, %{binding: binding, operation: @operations[type]}}
    end
  end

  def admit(_runtime, %Admission{prepared_input: []}, _opts), do: {:ok, nil}

  def admit(_runtime, %Admission{prepared_input: realms, signal: %{type: type}}, opts) do
    with {:ok, bindings} <- bind_realms(realms, opts) do
      {:ok, %{bindings: bindings, operation: @signals[type]}}
    end
  end

  @doc false
  def binding(%{binding: binding}, nil), do: {:ok, binding}
  def binding(%{bindings: _}, nil), do: {:error, :realm_name_required}

  def binding(%{bindings: bindings}, name) when is_atom(name) or is_binary(name) do
    case Map.fetch(bindings, to_string(name)) do
      {:ok, backend} -> {:ok, backend}
      :error -> {:error, :unknown_realm}
    end
  end

  def binding(_runtime, _name), do: {:error, :unknown_realm}

  defp bind_realms(realms, opts) do
    names = Enum.map(realms, & &1.name)

    case Keyword.fetch(opts, :bindings) do
      {:ok, bindings} when is_map(bindings) and map_size(bindings) == length(names) ->
        Enum.reduce_while(realms, {:ok, %{}}, fn %{name: name, profile: profile}, {:ok, bound} ->
          with {:ok, options} <- Map.fetch(bindings, name),
               {:ok, binding} <- bind_backend(options, profile),
               {:ok, binding} <- bind_presenter(binding, Keyword.get(options, :presenter)) do
            {:cont, {:ok, Map.put(bound, Atom.to_string(name), binding)}}
          else
            :error -> {:halt, {:error, {:realm_binding_required, name}}}
            {:error, reason} -> {:halt, {:error, {:invalid_realm_binding, name, reason}}}
          end
        end)

      _ ->
        {:error, :realm_bindings_must_match_declarations}
    end
  end

  defp bind_presenter(binding, nil), do: {:ok, binding}

  defp bind_presenter(binding, {module, _} = presenter) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :publish, 3),
      do: {:ok, Map.put(binding, :presenter, presenter)},
      else: {:error, :invalid_artifact_presenter}
  end

  defp bind_presenter(_, _), do: {:error, :invalid_artifact_presenter}

  defp bind_backend(opts, profile \\ :files) do
    if Keyword.keyword?(opts) do
      grants = Keyword.get(opts, :grants, :all)

      case Keyword.take(opts, [:root, :backend, :session]) do
        [session: pid] when is_pid(pid) ->
          with {:ok, requirements} <- Profile.resolve(profile),
               do: {:ok, %{target: {:session, pid, requirements}, grants: grants}}

        [root: root] when profile == :files and is_binary(root) ->
          if Path.type(root) == :absolute,
            do: {:ok, %{target: {Local, root}, grants: grants}},
            else: {:error, :realm_root_required}

        [backend: {module, _handle} = backend] when profile == :files and is_atom(module) ->
          if Code.ensure_loaded?(module) and function_exported?(module, :run, 4),
            do: {:ok, %{target: backend, grants: grants}},
            else: {:error, :invalid_realm_backend}

        [] ->
          {:error, :realm_root_required}

        [{first, _}, {second, _}]
        when first in [:root, :backend] and second in [:root, :backend] ->
          {:error, :conflicting_realm_options}

        _ ->
          {:error, :invalid_realm_backend}
      end
    else
      {:error, :invalid_realm_backend}
    end
  end
end
