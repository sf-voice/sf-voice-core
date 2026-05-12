defmodule EllieAi.Reconciliation do
  @moduledoc "cron module — each job is an independent timer with its own interval and tick."

  use GenServer

  import Ecto.Query
  require Logger

  alias EllieAi.{Customers, Menu, Orgs, Repo, Resto}
  alias EllieAi.Calls.{Call, Constants}

  # cadences are domain decisions, not ops knobs — no runtime config block.
  @jobs %{
    customers: %{
      enabled: true,
      interval_ms: 24 * 60 * 60 * 1000,
      # short initial delay so we don't hammer resto the moment the app boots.
      initial_delay_ms: 60_000
    },
    menu: %{
      enabled: true,
      interval_ms: 5 * 60 * 1000,
      initial_delay_ms: 30_000
    },
    stale_calls: %{
      enabled: true,
      interval_ms: 5 * 60 * 1000,
      # run shortly after boot so a deploy that interrupted a call gets
      # its orphan row swept fast, not after 5min.
      initial_delay_ms: 15_000
    }
  }

  # a real call exceeds 30min only in pathological cases. anything past
  # that with status still ringing/active is almost certainly orphaned.
  @stale_call_max_age_seconds 30 * 60

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def run_now do
    Map.new(@jobs, fn {job, _} -> {job, run_job_sync(job)} end)
  end

  def run_now(job) when is_map_key(@jobs, job) do
    run_job_sync(job)
  end

  @impl true
  def init(state) do
    Enum.each(@jobs, fn {job, meta} ->
      if enabled?(job) do
        Process.send_after(self(), {:run, job}, meta.initial_delay_ms)
      end
    end)

    {:ok, state}
  end

  @impl true
  def handle_info({:run, job}, state) when is_map_key(@jobs, job) do
    _ = run_job_sync(job)
    Process.send_after(self(), {:run, job}, interval_ms(job))
    {:noreply, state}
  end

  defp do_customers(org) do
    Customers.reconcile_from_resto(org)
  end

  defp do_menu(org) do
    case Resto.list_menu_items(org) do
      {:ok, items} -> Menu.reconcile(org.id, items)
      {:error, _} = err -> err
    end
  end

  # bypasses the changeset path because these rows are orphans by definition —
  # whatever process owned them is gone. `hangup_reason: "stale_sweep"` lets
  # operators distinguish these from real `call.hangup`-driven endings.
  defp do_stale_calls(org) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    cutoff = DateTime.add(now, -@stale_call_max_age_seconds, :second)
    active_statuses = [Constants.status_ringing(), Constants.status_active()]

    {count, _} =
      from(c in Call,
        where:
          c.org_id == ^org.id and
            c.status in ^active_statuses and
            is_nil(c.ended_at) and
            c.started_at < ^cutoff
      )
      |> Repo.update_all(
        set: [
          status: Constants.status_ended(),
          hangup_reason: "stale_sweep",
          ended_at: now,
          updated_at: now
        ]
      )

    {:ok, count}
  end

  defp run_job_sync(job) do
    Enum.map(Orgs.list_with_resto_config(), fn org ->
      result = dispatch(job, org)
      log_result(job, org, result)
      {org.slug, result}
    end)
  end

  defp dispatch(:customers, org), do: do_customers(org)
  defp dispatch(:menu, org), do: do_menu(org)
  defp dispatch(:stale_calls, org), do: do_stale_calls(org)

  defp log_result(:customers, org, {:ok, count}),
    do: Logger.info("reconcile #{org.slug}: synced #{count} customers")

  defp log_result(:menu, org, {:ok, %{upserted: u, deleted: d}}),
    do: Logger.info("menu #{org.slug}: +#{u} / -#{d}")

  # quiet when there's nothing to sweep — common case is 0, runs every 5min.
  defp log_result(:stale_calls, _org, {:ok, 0}), do: :ok

  defp log_result(:stale_calls, org, {:ok, count}),
    do:
      Logger.info(
        "stale_calls #{org.slug}: ended #{count} orphan call row(s) " <>
          "(hangup_reason=stale_sweep)"
      )

  defp log_result(job, org, {:error, reason}),
    do: Logger.warning("#{job} #{org.slug}: failed — #{inspect(reason)}")

  defp log_result(_job, _org, _other), do: :ok

  defp enabled?(job), do: @jobs[job].enabled
  defp interval_ms(job), do: @jobs[job].interval_ms
end
