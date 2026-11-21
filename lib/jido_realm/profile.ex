defmodule Jido.Realm.Profile do
  @moduledoc """
  Reusable requirements for opening a Realm.

  The agent can use `:files`, `:program`, or a module that implements
  `requirements/0`. The host selects the provider and can restrict access.

  Use `:execution_controls` to require controls from the selected runner
  for a declared runtime. A runtime that cannot supply every listed control
  is unavailable for that profile.
  """

  defstruct required: [:files], optional: [], execution_controls: %{}

  @type t :: %__MODULE__{
          required: [atom()],
          optional: [atom()],
          execution_controls: %{atom() => [atom()]}
        }
  @callback requirements() :: t()

  @doc false
  def resolve(:files) do
    {:ok, %__MODULE__{optional: [:tree, :revisions, :search, :streams, :reconcile, :commands]}}
  end

  def resolve(:program) do
    {:ok, files} = resolve(:files)

    {:ok,
     %{
       files
       | optional:
           files.optional ++
             [:preview, :services, :ports, :background, :snapshots | Jido.Realm.Runner.runtimes()]
     }}
  end

  def resolve(module) when is_atom(module) do
    with true <- Code.ensure_loaded?(module) and function_exported?(module, :requirements, 0),
         %__MODULE__{required: required, optional: optional} = profile <- module.requirements(),
         true <- valid_capabilities?(required) and valid_capabilities?(optional),
         true <- :files in required,
         true <- valid_controls?(profile.execution_controls, required ++ optional) do
      {:ok, %{profile | required: Enum.uniq(required), optional: Enum.uniq(optional)}}
    else
      _ -> {:error, :invalid_realm_profile}
    end
  end

  defp valid_capabilities?(values) do
    is_list(values) and Enum.all?(values, &(is_atom(&1) and &1 not in [nil, true, false]))
  end

  defp valid_controls?(controls, declared) when is_map(controls) do
    runtimes = Jido.Realm.Runner.runtimes()

    Enum.all?(controls, fn {runtime, required} ->
      runtime in declared and runtime in runtimes and valid_capabilities?(required)
    end)
  end

  defp valid_controls?(_, _), do: false

  @doc false
  def admit(%__MODULE__{} = profile, report, permitted) do
    verified = for {key, true} <- report, permitted == :all or key in permitted, do: key

    case profile.required -- verified do
      [] -> {:ok, Enum.filter(Enum.uniq(profile.required ++ profile.optional), &(&1 in verified))}
      [missing | _] -> {:error, {:required_capability_unavailable, missing}}
    end
  end
end
