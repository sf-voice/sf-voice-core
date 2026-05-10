# compile-time configuration for ellie_ai. environment-specific overrides
# live in {dev,test,prod,runtime}.exs and are imported at the bottom.

import Config

config :ellie_ai,
  ecto_repos: [EllieAi.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# every read-model field is dictated by what resto exposes; ellie owns no
# customer state of its own. base_url is composed at compile time from
# `RESTO_BOOKING_APP_PORT` (the only resto-related env var we keep in
# dev); runtime.exs overrides with `RESTO_BASE_URL` when set (prod) so
# split-host deploys aren't stuck on localhost.
config :ellie_ai, EllieAi.Resto,
  base_url: "http://localhost:#{System.get_env("RESTO_BOOKING_APP_PORT", "4000")}",
  # how long the http client waits before giving up on a single resto call.
  # ellie's call paths play a "one moment while i look that up" filler if a
  # tool exec stretches past a couple seconds, so this can be generous.
  receive_timeout: 5_000

# the reconciliation cron is on by default; test env disables it so the
# suite never reaches out to a resto we haven't stubbed.
config :ellie_ai, EllieAi.Reconciliation,
  enabled: true,
  # full pull-all-customers refresh interval. 24h is the operational
  # default — tighten in test or when debugging drift.
  interval_ms: 24 * 60 * 60 * 1000

# menu cache reconciliation runs much more often than the customer
# cache because menu changes are minutes, not days.
config :ellie_ai, EllieAi.MenuReconciliation,
  enabled: true,
  interval_ms: 5 * 60 * 1000

config :ellie_ai, EllieAiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EllieAiWeb.ErrorHTML, json: EllieAiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EllieAi.PubSub,
  # liveview signing salt — keep stable across restarts so live sessions
  # survive a hot reload. *not* a secret in v0; replace via runtime.exs
  # in prod if/when staff sessions actually need to be tamper-evident.
  live_view: [signing_salt: "ellie-staff-ui-v0-salt"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
