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
