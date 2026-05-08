defmodule RestoBookingApp.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :resto_booking_app

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  run the demo seed file. called from the deploy script after a release boot
  so the floor plan always has rolling demo data — yesterday, today, and the
  next two days. the seed script wipes its own four-day window before
  inserting, so running this on every deploy keeps the demo fresh without
  duplicating rows.
  """
  def seed do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(RestoBookingApp.Repo, fn _repo -> run_seeds() end)
  end

  defp run_seeds do
    seeds_path = Application.app_dir(@app, "priv/repo/seeds.exs")
    Code.eval_file(seeds_path)
    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
