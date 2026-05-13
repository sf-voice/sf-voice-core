defmodule EllieAi.Release do
  @moduledoc """
  release-time db tasks. invoked from the deploy script via:

      /app/bin/ellie_ai eval "EllieAi.Release.migrate()"
      /app/bin/ellie_ai eval "EllieAi.Release.seed()"

  the supervision tree also auto-migrates on boot (see Application);
  `migrate/0` here is for manual ops / re-running after a rollback.
  """

  @app :ellie_ai

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
  run the demo seed file. called from the deploy script after each
  release boot — the deploy wipes the sqlite file every push, so this
  is what re-creates the seasons group + orgs the booting banner
  expects.
  """
  def seed do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(EllieAi.Repo, fn _repo -> run_seeds() end)
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
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
