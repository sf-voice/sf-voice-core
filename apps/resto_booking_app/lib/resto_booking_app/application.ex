defmodule RestoBookingApp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # halt early with a clean banner if any required env var is missing.
    # skipped in :test so the suite doesn't have to set bogus values.
    RestoBookingApp.EnvCheck.validate!()

    children = [
      RestoBookingAppWeb.Telemetry,
      RestoBookingApp.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:resto_booking_app, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:resto_booking_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RestoBookingApp.PubSub},
      RestoBookingAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: RestoBookingApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    RestoBookingAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    System.get_env("RELEASE_NAME") == nil
  end
end
