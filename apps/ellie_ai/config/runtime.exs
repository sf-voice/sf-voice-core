import Config

# `mix phx.server` starts the endpoint in dev/test automatically. for prod
# releases the supervisor only starts the endpoint when PHX_SERVER=true.
if System.get_env("PHX_SERVER") do
  config :ellie_ai, EllieAiWeb.Endpoint, server: true
end

# port is configurable in every env so the same Dockerfile works locally and
# in production. defaults to 4001 to match dev.exs.
config :ellie_ai, EllieAiWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4001"))]

# resto base url for the customer-summary integration. prefers an explicit
# `RESTO_BASE_URL` (set in prod where resto and ellie live on different
# hosts); falls back to composing `http://localhost:$RESTO_BOOKING_APP_PORT`
# for the dev workflow, where the only resto-related env var is the port.
config :ellie_ai, EllieAi.RestoClient,
  base_url:
    System.get_env("RESTO_BASE_URL") ||
      "http://localhost:#{System.get_env("RESTO_BOOKING_APP_PORT", "4000")}"

# bearer used to call resto's /api/* — same value resto reads from its own
# env. dev/test fall back to a placeholder; prod refuses to boot without
# one (so a misconfigured deploy can't silently fail-open against resto).
internal_api_token =
  case {System.get_env("INTERNAL_API_TOKEN"), config_env()} do
    {token, _} when is_binary(token) and token != "" -> token
    {_, :prod} -> raise "environment variable INTERNAL_API_TOKEN is missing in prod"
    {_, :test} -> "test-internal-api-token"
    {_, _} -> "dev-internal-api-token-not-for-prod"
  end

config :ellie_ai, :internal_api_token, internal_api_token

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: System.get_env("AWS_REGION", "us-west-1")

config :ex_aws, :hackney_opts, recv_timeout: 30_000

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/ellie_ai/ellie_ai.db
      """

  config :ellie_ai, EllieAi.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      generate one with: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :ellie_ai, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ellie_ai, EllieAiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # ipv6 dual-stack so the container binds whichever address docker hands it
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
