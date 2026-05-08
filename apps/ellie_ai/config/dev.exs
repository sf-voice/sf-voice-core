import Config

# dev endpoint port comes from ELLIE_AI_PORT in the workspace `.env` (loaded
# by mise). default 4001 keeps it side-by-side with resto_booking_app on 4000.
config :ellie_ai, EllieAiWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: String.to_integer(System.get_env("ELLIE_AI_PORT", "4321"))
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "EllieAiDevSecretKeyBaseAtLeast64BytesLongPlaceholderXyzAbc1234567890",
  watchers: []

config :ellie_ai, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
