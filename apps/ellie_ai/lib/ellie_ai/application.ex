defmodule EllieAi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EllieAiWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ellie_ai, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EllieAi.PubSub},
      # Start a worker by calling: EllieAi.Worker.start_link(arg)
      # {EllieAi.Worker, arg},
      # Start to serve requests, typically the last entry
      EllieAiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EllieAi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EllieAiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
