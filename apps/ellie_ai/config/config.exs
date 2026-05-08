# compile-time configuration for ellie_ai. environment-specific overrides
# live in {dev,test,prod,runtime}.exs and are imported at the bottom.

import Config

config :ellie_ai,
  generators: [timestamp_type: :utc_datetime]

config :ellie_ai, EllieAiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: EllieAiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EllieAi.PubSub

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
