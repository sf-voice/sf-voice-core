import Config

# in-memory sqlite for tests so the suite is deterministic and parallel-safe.
# the `:memory:` form lives only for the connection's lifetime; ecto's
# sandbox handles transaction rollback between tests.
# on-disk test db — sqlite's `:memory:` is per-connection so migrations
# don't survive between sandbox checkouts. follow resto's pattern: a real
# file under priv/data/ and the sandbox handles transaction rollback.
config :ellie_ai, EllieAi.Repo,
  database: Path.expand("../priv/data/ellie_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

# test endpoint on 4003 — booking's test endpoint is 4002. server is off
# during tests; this is just here so url generation works in test cases.
config :ellie_ai, EllieAiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "EllieAiTestSecretKeyBaseAtLeast64BytesLongPlaceholderXyzAbc1234567890",
  server: false

# tests stub resto via Bypass; never reach out for real.
config :ellie_ai, EllieAi.Resto, base_url: "http://localhost:0"

# the reconciliation crons must not auto-fire during tests — they'd race
# with whatever bypass stub the test set up.
config :ellie_ai, EllieAi.Reconciliation, enabled: false
config :ellie_ai, EllieAi.MenuReconciliation, enabled: false

# bearer token for the test runtime — value here matches what the test
# suite sends to resto (when there's a stub). no real auth happens.
config :ellie_ai, :internal_api_token, "test-internal-api-token"

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
