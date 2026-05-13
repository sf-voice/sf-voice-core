defmodule EllieAi.Application do
  use Application

  @impl true
  def start(_type, _args) do
    EllieAi.EnvCheck.validate!()

    # load silero vad once per vm
    EllieAi.Calls.SileroVad.load!()

    # owned by the application controller process so the table survives any
    # request/worker dying. created here (not lazily by callers) because a
    # short-lived plug process owning a named ETS table would take the
    # whole cache down on exit. see EllieAi.Settings.
    init_settings_cache()

    children =
      [
        EllieAiWeb.Telemetry,
        EllieAi.Repo,
        # auto-migrate on boot in releases. dev/test skip this (mix
        # ecto.migrate handles dev; test setup creates schemas). without
        # this Reconciliation lower down crashes immediately on a fresh
        # sqlite file — "no such table: orgs".
        {Ecto.Migrator,
         repos: Application.fetch_env!(:ellie_ai, :ecto_repos), skip: skip_migrations?()},
        # tw_merge powers SaladUI's className conflict resolution. the
        # cache is an ETS table populated lazily on first merge — required
        # by SaladUI as of 1.0.0-beta.
        TwMerge.Cache,
        {DNSCluster, query: Application.get_env(:ellie_ai, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: EllieAi.PubSub},
        # registry for per-call processes (CallServer, AudioBridge,
        # MediaStreamingSocket) keyed by telnyx ccid.
        EllieAi.Calls.CallRegistry,
        # dynamic supervisor that owns one CallTree per active call.
        EllieAi.Calls.CallSupervisor,
        # in-memory dedup for inbound sms webhook ids (5-min TTL).
        EllieAi.Calls.SmsDedup,
        if(env() != :test, do: EllieAi.Reconciliation),
        EllieAiWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # supervisor options: https://hexdocs.pm/elixir/Supervisor.html
    opts = [strategy: :one_for_one, name: EllieAi.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _} = result ->
        log_boot_banner()
        result

      other ->
        other
    end
  end


  defp log_boot_banner do
    if env() != :test do
      try do
        orgs = EllieAi.Orgs.list()

        rows =
          orgs
          |> Enum.map(fn o ->
            "│    • #{String.pad_trailing(o.slug, 16)} → #{o.telnyx_phone_number || "(no telnyx number set)"}"
          end)
          |> Enum.join("\n")

        webhook =
          case System.get_env("NGROK_URL") do
            nil -> "http://localhost:#{port()}/telnyx/webhook"
            url -> "#{url}/telnyx/webhook"
          end

        IO.puts("""

        ╭─ ellie ready ──────────────────────────────────────────────────────────
        │
        │  dial to ring ellie:
        #{if rows == "", do: "│    (no orgs seeded — run `mix run priv/repo/seeds.exs`)", else: rows}
        │
        │  telnyx voice api app webhook url:
        │    #{webhook}
        │
        │  staff ui: http://localhost:#{port()}/
        │
        ╰────────────────────────────────────────────────────────────────────────
        """)
      rescue
        e ->
          require Logger
          Logger.warning("could not print boot banner: #{Exception.message(e)}")
      end
    end
  end

  defp init_settings_cache do
    if :ets.whereis(:ellie_settings_cache) == :undefined do
      :ets.new(:ellie_settings_cache, [
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    :ok
  end

  defp port do
    Application.get_env(:ellie_ai, EllieAiWeb.Endpoint, [])
    |> Keyword.get(:http, [])
    |> Keyword.get(:port, 4321)
  end

  defp env do
    cond do
      Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) -> Mix.env()
      System.get_env("RELEASE_NAME") -> :prod
      true -> :prod
    end
  end

  # release builds set RELEASE_NAME; dev/test don't. only auto-migrate
  # inside a release so `mix ecto.migrate` keeps owning dev migrations
  # and the test suite isn't surprised by an extra child.
  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end

  @impl true
  def config_change(changed, _new, removed) do
    EllieAiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
