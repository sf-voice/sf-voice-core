
import Config

config :ellie_ai,
  ecto_repos: [EllieAi.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :ellie_ai, EllieAi.Resto,
  base_url: "http://localhost:#{System.get_env("RESTO_BOOKING_APP_PORT", "4000")}",
  # how long the http client waits before giving up
  receive_timeout: 5_000

config :ellie_ai, EllieAiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EllieAiWeb.ErrorHTML, json: EllieAiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EllieAi.PubSub,
  live_view: [signing_salt: "ellie-staff-ui-v0-salt"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
