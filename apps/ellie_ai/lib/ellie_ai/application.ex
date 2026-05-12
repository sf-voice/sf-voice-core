defmodule EllieAi.Application do
  use Application

  @impl true
  def start(_type, _args) do
    EllieAi.EnvCheck.validate!()

    # load silero vad once per vm
    EllieAi.Calls.SileroVad.load!()

    children =
      [
        EllieAiWeb.Telemetry,
        EllieAi.Repo,
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

  @impl true
  def config_change(changed, _new, removed) do
    EllieAiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
