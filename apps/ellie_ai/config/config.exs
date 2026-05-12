
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

# asset pipeline — mirrors resto's tailwind v4 + esbuild setup so the two
# apps stay legible side by side. tailwind config and entry point live
# under apps/ellie_ai/assets/.
config :esbuild,
  version: "0.25.4",
  ellie_ai: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.12",
  ellie_ai: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

import_config "#{config_env()}.exs"
