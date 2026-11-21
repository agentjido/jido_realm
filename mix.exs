defmodule Jido.Realm.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_realm"
  @description "Working files, execution environments, and previews for Jido agents"
  @shell_ref "d2666d11cd082345b7c2b11328cfc5f6c89c88d5"
  @vfs_ref "d8e473ca68c6e230f9aac2e63b9da47cc5382c0d"

  def project do
    [
      app: :jido_realm,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_ignore_filters: [&integration_fixture?/1],

      # Documentation
      name: "Jido.Realm",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Test Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90]
      ],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.examples": :test,
        "test.realm": :test,
        "test.coverage": :test,
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :sasl, :ssh, :public_key, :inets, :ssl],
      mod: {Jido.Realm.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp integration_fixture?(path) do
    Path.basename(path) in [
      "apple_edit_guest.exs",
      "apple_edit_tools.exs",
      "sprite_app_fixture.exs"
    ]
  end

  defp deps do
    [
      # Runtime
      shell_dep(),
      vfs_dep(),
      {:zoi, "~> 0.19.0"},
      {:splode, "~> 0.3.0"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      # Enable the optional Bash backend in Shell.
      {:bash, "~> 0.6.0"},
      {:erlexec, "~> 2.6.0"},
      {:lua, "~> 1.0.2"},
      {:jido, github: "agentjido/jido", ref: "aa61e26d50f8035dcffd9149515e60fcda9dcc6a"},
      {:sprites, "~> 0.2.4"},
      # Sprites 0.2.4 caps Cowlib at 2.19. Use the 2.22 security fixes.
      {:cowlib, "~> 2.22.0", override: true},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:minio_server, "~> 0.4.0", only: [:dev, :test]}
    ]
  end

  defp shell_dep do
    case System.get_env("JIDO_SHELL_PATH") do
      nil -> {:jido_shell, github: "agentjido/jido_shell", ref: @shell_ref}
      path -> {:jido_shell, path: Path.expand(path)}
    end
  end

  defp vfs_dep do
    case System.get_env("JIDO_VFS_PATH") do
      nil -> {:jido_vfs, github: "agentjido/jido_vfs", ref: @vfs_ref, override: true}
      path -> {:jido_vfs, path: Path.expand(path)}
    end
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      "test.examples": &examples/1,
      "test.realm": &realm_examples/1,
      "test.integration": &integration/1,
      "test.coverage": &coverage/1,
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer",
        "doctor --raise"
      ]
    ]
  end

  defp package do
    [
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "README.md",
        "HOST.md",
        "VISION.md",
        "config",
        "lib",
        "src",
        "API_SPEC.md",
        "SANDBOX.md",
        "DEPLOY.md",
        "docs/guides",
        "docs/source-imports.md",
        "docs/workspace-asset-lifecycle.md",
        "mix.exs",
        "usage-rules.md"
      ],
      maintainers: ["Agent Jido Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/jido_realm/changelog.html",
        "Discord" => "https://agentjido.xyz/discord",
        "Documentation" => "https://hexdocs.pm/jido_realm",
        "GitHub" => @source_url,
        "Website" => "https://agentjido.xyz"
      }
    ]
  end

  defp docs do
    guide_groups = [
      "Start here": [
        {"docs/guides/table_of_contents.md", filename: "guides"},
        {"README.md", title: "Jido Realm"},
        {"HOST.md", title: "Realm host API"},
        {"docs/guides/first-realm.md", title: "First Realm"},
        {"docs/guides/files.md", title: "Realm files"},
        {"docs/guides/exec.md", title: "Realm execution"},
        {"docs/guides/services.md", title: "Realm services"},
        {"docs/guides/artifacts.md", title: "Realm artifacts"},
        {"docs/guides/providers.md", title: "Realm providers"}
      ],
      "Execution and delivery": [
        {"SANDBOX.md", title: "Run in a sandbox"},
        {"DEPLOY.md", title: "Deploy a saved result"}
      ],
      Maintenance: [
        {"CONTRIBUTING.md", title: "Contributing"},
        {"docs/source-imports.md", title: "Imported source"},
        {"CHANGELOG.md", title: "Change log"},
        {"LICENSE", title: "License"}
      ],
      "Earlier designs": [
        {"API_SPEC.md", title: "Realm host API proposal"},
        {"docs/workspace-asset-lifecycle.md", title: "Realm asset lifecycle proposal"}
      ]
    ]

    [
      main: "guides",
      source_ref: "v#{@version}",
      extra_section: "Guides",
      groups_for_modules: [
        Host: [
          Jido.Realm.Host,
          Jido.Realm.Host.Handle,
          Jido.Realm.Host.Entry,
          Jido.Realm.Host.Error,
          Jido.Realm.Host.Execution,
          Jido.Realm.Host.FileView,
          Jido.Realm.Host.Info
        ],
        "Durable references": [
          Jido.Realm.Host.Snapshot,
          Jido.Realm.Host.InfrastructureRef,
          Jido.Realm.Host.CommandRef
        ],
        "Profiles and providers": [
          Jido.Realm.Host.Profile,
          Jido.Realm.Host.Policy,
          Jido.Realm.Host.Provider,
          Jido.Realm.Host.Schemas
        ],
        Sandboxes: ~r/^Jido\.Realm\.Host\.Sandbox(\.|$)/,
        Deployment: ~r/^Jido\.Realm\.Host\.Deploy(\.|$)/
      ],
      nest_modules_by_prefix: [
        Jido.Realm.Host.Sandbox,
        Jido.Realm.Host.Deploy
      ],
      extras: Enum.flat_map(guide_groups, &elem(&1, 1)),
      groups_for_extras:
        for {group, guides} <- guide_groups do
          {group, Enum.map(guides, &elem(&1, 0))}
        end
    ]
  end

  defp examples(args) do
    Mix.Task.run(
      "test",
      numbered_example_files() ++ ["--include", "integration" | args]
    )
  end

  defp realm_examples(args) do
    files =
      Enum.flat_map(
        ["examples/realm", "test/integration"],
        &Path.wildcard(&1 <> "/**/*_test.exs")
      )

    Mix.Task.run("test", files ++ args)
  end

  defp integration(args) do
    for file <- integration_example_files() do
      {_, status} =
        System.cmd("mix", ["test", file, "--include", "integration"] ++ args,
          into: IO.stream(),
          env: [{"MIX_ENV", "test"}]
        )

      if status != 0, do: Mix.raise("Integration example failed: #{file}")
    end
  end

  defp coverage(args) do
    output = "cover/examples"
    File.rm_rf!(output)
    File.mkdir_p!(output)

    for {file, index} <- Enum.with_index(integration_example_files()) do
      coverage_run(
        [
          "coveralls.json",
          file,
          "--include",
          "integration",
          "--export-coverage",
          "examples/#{index}"
        ] ++
          args
      )
    end

    coverage_run(["coveralls.json", "--import-cover", output] ++ args)
    coverage_run(["coveralls", "--import-cover", output] ++ args)
  end

  defp coverage_run(args) do
    {_, status} =
      System.cmd("mix", args,
        into: IO.stream(),
        env: [{"MIX_ENV", "test"}, {"JIDO_COVERAGE_DIR", Path.expand("cover/examples")}]
      )

    if status != 0, do: Mix.raise("Coverage test run failed")
  end

  defp integration_example_files do
    numbered_example_files() ++ Path.wildcard("test/examples/**/*_test.exs")
  end

  defp numbered_example_files, do: Path.wildcard("examples/[0-9][0-9]_*/**/*_test.exs")
end
