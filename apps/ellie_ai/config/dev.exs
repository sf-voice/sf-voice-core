import Config


config :ellie_ai, EllieAi.Repo,
  database: Path.expand("../priv/data/ellie.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  log: false

config :ellie_ai, EllieAiWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: String.to_integer(System.get_env("ELLIE_AI_PORT", "4001"))
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "EllieAiDevSecretKeyBaseAtLeast64BytesLongPlaceholderXyzAbc1234567890",
  watchers: []

config :ellie_ai, dev_routes: true


config :logger, :default_formatter,
  format: "[$level] $metadata$message\n",
  metadata: [:ccid, :direction, :event_type]

config :logger, level: :info

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
