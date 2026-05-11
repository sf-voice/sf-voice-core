import Config


config :ellie_ai, EllieAi.Repo,
  database: Path.expand("../priv/data/ellie_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :ellie_ai, EllieAiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "EllieAiTestSecretKeyBaseAtLeast64BytesLongPlaceholderXyzAbc1234567890",
  server: false

  # don't need a real endpoint here
config :ellie_ai, EllieAi.Resto, base_url: "http://localhost:0"

config :ellie_ai, :internal_api_token, "test-internal-api-token"

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
