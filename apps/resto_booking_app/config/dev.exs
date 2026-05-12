import Config

# on-disk sqlite — survives restarts so trolls' bookings stick around
config :resto_booking_app, RestoBookingApp.Repo,
  database: Path.expand("../priv/data/resto.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :resto_booking_app, RestoBookingAppWeb.Endpoint,
  # port comes from RESTO_BOOKING_APP_PORT in the workspace `.env` (loaded
  # by mise) so both phoenix apps can run side-by-side without colliding.
  http: [
    ip: {127, 0, 0, 1},
    port: String.to_integer(System.get_env("RESTO_BOOKING_APP_PORT", "4000"))
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "pnXKOlkxWhcMNKKuzT2G1WXARi4OgDPAUzF878XZmSkLZYKY3hGzw3yv1XqmIo3a",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:resto_booking_app, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:resto_booking_app, ~w(--watch)]}
  ]

config :resto_booking_app, RestoBookingAppWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/resto_booking_app_web/router\.ex$",
      ~r"lib/resto_booking_app_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

config :resto_booking_app, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
