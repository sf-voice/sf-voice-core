import Config

# test endpoint on 4003 — booking's test endpoint is 4002. server is off
# during tests; this is just here so url generation works in test cases.
config :ellie_ai, EllieAiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "EllieAiTestSecretKeyBaseAtLeast64BytesLongPlaceholderXyzAbc1234567890",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
