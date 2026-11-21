defmodule RealmWorkbench.MixProject do
  use Mix.Project

  def project do
    [
      app: :realm_workbench,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps_path: Path.expand("../../../tmp/coding-agent-workbench/deps", __DIR__),
      deps: deps()
    ]
  end

  def application do
    [mod: {RealmWorkbench, []}, extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:jido_realm, path: "../../.."},
      {:phoenix, "1.8.17"},
      {:bandit, "1.15.0"}
    ]
  end
end
