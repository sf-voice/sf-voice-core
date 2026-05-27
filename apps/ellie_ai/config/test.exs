import Config

config :ellie_ai, EllieAi.Repo,
  database: Path.expand("../priv/data/ellie_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :ellie_ai, EllieAiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "EllieAiTestSecretKeyBaseAtLeast64BytesLongPlaceholderXyzAbc1234567890",
  server: false

# keep outbound http inside the test process; the socket sandbox blocks Bypass listeners.
config :ellie_ai, EllieAi.RestoClient,
  base_url: "http://localhost:0",
  req_options: [plug: {Req.Test, EllieAi.RestoClient}, retry_delay: 0]

config :ellie_ai, EllieAi.Telnyx.Client,
  req_options: [plug: {Req.Test, EllieAi.Telnyx.Client}, retry_delay: 0]

config :ellie_ai, EllieAi.Providers.OpenAI,
  req_options: [plug: {Req.Test, EllieAi.Providers.OpenAI}, retry_delay: 0]

config :ellie_ai, EllieAi.Evals.PromptRunner,
  req_options: [plug: {Req.Test, EllieAi.Evals.PromptRunner}, retry_delay: 0]

config :ellie_ai, EllieAi.Calls.CallTree, audio_bridge: EllieAi.Calls.AudioBridgeStub

config :ellie_ai, :internal_api_token, "test-internal-api-token"

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
