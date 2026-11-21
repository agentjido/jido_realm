defmodule Mix.Tasks.JidoRealm.Doctor do
  use Mix.Task

  alias Jido.Realm.Doctor

  @shortdoc "Check Jido Realm host and test prerequisites"
  @moduledoc """
  Checks local prerequisites for Realm and its opt-in test lanes.

      mix jido_realm.doctor
      mix jido_realm.doctor --lane docker --format json --strict

  The available lanes are `core`, `native`, `docker`, `browser`,
  `apple_container`, `sprites`, `live_sprite`, and `lmstudio`.

  The default report checks all lanes and exits successfully. Use `--strict`
  to fail if a selected lane needs attention. Use `--lane` to select one
  lane. The JSON report goes to stdout, including when `--strict` fails.
  A ready lane has passed preflight. Its bindings still need conformance tests.
  """

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [format: :string, lane: :string, strict: :boolean])

    if rest != [] or invalid != [], do: Mix.raise("Invalid jido_realm.doctor options")

    format = Keyword.get(opts, :format, "text")
    if format not in ["text", "json"], do: Mix.raise("Use --format text or --format json")

    lanes = select_lanes(Keyword.get(opts, :lane))
    Mix.Task.run("loadpaths", ["--no-deps-check"])
    report = Doctor.report(lanes)

    case format do
      "text" -> print(report)
      "json" -> Mix.shell().info(JSON.encode!(report))
    end

    if Keyword.get(opts, :strict, false) and Enum.any?(report.lanes, &(&1.status == :attention)) do
      Mix.raise("Realm preflight requires attention")
    end
  end

  defp select_lanes(nil), do: Doctor.lanes()

  defp select_lanes(name) do
    case Enum.find(Doctor.lanes(), &(Atom.to_string(&1) == name)) do
      nil -> Mix.raise("Select a lane from #{Enum.join(Doctor.lanes(), ", ")}")
      lane -> [lane]
    end
  end

  defp print(%{host: host, lanes: lanes}) do
    Mix.shell().info("#{host.os} #{host.architecture} | Elixir #{host.elixir} | OTP #{host.otp}")

    for lane <- lanes do
      Mix.shell().info("\n#{lane.name} | #{lane.status}")

      for check <- lane.checks do
        Mix.shell().info("  #{check.id} | #{check.status} | #{check.detail}")
      end
    end
  end
end
