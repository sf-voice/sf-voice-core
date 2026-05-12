import Config

config :resto_booking_app,
  ecto_repos: [RestoBookingApp.Repo],
  generators: [timestamp_type: :utc_datetime],
  # the restaurant's local timezone — drives every human-facing date/time
  # decision (opening hours, floor-plan day grouping, slot construction).
  # storage stays utc; this only governs interpretation.
  timezone: "America/Los_Angeles"

# tz package provides the iana time zone database. without this elixir's
# default UTCOnlyTimeZoneDatabase rejects any non-utc zone at runtime.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :resto_booking_app, RestoBookingAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RestoBookingAppWeb.ErrorHTML, json: RestoBookingAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RestoBookingApp.PubSub,
  live_view: [signing_salt: "fll+advj"]

config :esbuild,
  version: "0.25.4",
  resto_booking_app: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.12",
  resto_booking_app: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
