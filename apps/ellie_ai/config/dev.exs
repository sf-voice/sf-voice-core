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
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:ellie_ai, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:ellie_ai, ~w(--watch)]}
  ]

# reload the browser when the css/js bundle or any web module changes.
config :ellie_ai, EllieAiWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/ellie_ai_web/router\.ex$",
      ~r"lib/ellie_ai_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

config :ellie_ai, dev_routes: true

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true


config :logger, :default_formatter,
  format: "[$level] $metadata$message\n",
  metadata: [:ccid, :direction, :event_type]

config :logger, level: :info

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
