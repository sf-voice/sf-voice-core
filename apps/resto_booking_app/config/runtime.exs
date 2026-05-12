import Config

if System.get_env("PHX_SERVER") do
  config :resto_booking_app, RestoBookingAppWeb.Endpoint, server: true
end

config :resto_booking_app, RestoBookingAppWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# bearer token gating /api/* — shared with ellie_ai via env. always read it
# at runtime so blue-green container swaps can rotate the value without a
# code deploy. prod refuses to boot without one; dev/test fall back to a
# stable placeholder so the test suite and curl-from-localhost both work.
internal_api_token =
  case {System.get_env("INTERNAL_API_TOKEN"), config_env()} do
    {token, _} when is_binary(token) and token != "" -> token
    {_, :prod} -> raise "environment variable INTERNAL_API_TOKEN is missing in prod"
    {_, _} -> "dev-internal-api-token-not-for-prod"
  end

config :resto_booking_app, :internal_api_token, internal_api_token

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/resto_booking_app/resto_booking_app.db
      """

  config :resto_booking_app, RestoBookingApp.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :resto_booking_app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :resto_booking_app, RestoBookingAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
