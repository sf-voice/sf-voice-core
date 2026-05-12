import Config

# keep the test db next to the dev db under priv/data/
config :resto_booking_app, RestoBookingApp.Repo,
  database: Path.expand("../priv/data/resto_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :resto_booking_app, RestoBookingAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TyRwj5nGEgIsbhTosKdox2FinQKfDfA8OxRAu/M6FF8rM7Nzk7f21l8XXfhevlWh",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true
