defmodule Jido.Realm.Conformance.Fixture do
  @moduledoc """
  Prepares one binding before the harness starts the agent.

  Supply an isolated placement or the prerequisites for one. Return plugin
  runtime options and a direct observer. A seed callback may set up inputs
  through the store. Let the agent open and close managed placements.
  Register cleanup of test-owned prerequisites with ExUnit.
  """

  @type observer :: (String.t() -> {:ok, binary()} | {:error, term()})

  @callback prepare(context :: map()) :: %{
              required(:runtime_options) => keyword(),
              required(:observe) => observer(),
              optional(:seed) => (String.t(), binary() -> term()),
              optional(atom()) => term()
            }
end
