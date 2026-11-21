import Config

config :realm_workbench,
  runs_dir: Path.expand("../../../../tmp/coding-agent-workbench/runs", __DIR__)

config :realm_workbench, RealmWorkbench.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("WORKBENCH_PORT", "4090"))],
  server: config_env() != :test,
  secret_key_base: Base.encode64(:crypto.strong_rand_bytes(64))

config :phoenix, :json_library, JSON
