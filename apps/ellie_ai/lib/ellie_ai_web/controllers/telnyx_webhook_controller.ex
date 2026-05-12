defmodule EllieAiWeb.TelnyxWebhookController do
  @moduledoc """
  inbound telnyx call webhooks. signature is verified upstream by
  `EllieAi.Telnyx.SignaturePlug`. v0 handles `call.initiated`,
  `call.answered`, `call.hangup`; everything else is logged and 200'd.
  idempotency comes from `EllieAi.Calls.spawn_or_noop/2`.
  """

  use EllieAiWeb, :controller

  alias EllieAi.{Calls, Orgs}
  alias EllieAi.Telnyx.Client

  require Logger

  def handle(conn, %{"data" => %{"event_type" => event_type, "payload" => payload} = data}) do
    Logger.info("telnyx webhook: #{event_type}")
    log_full_payload(event_type, data)
    handle_event(event_type, payload)
    send_resp(conn, 200, "")
  end

  def handle(conn, params) do
    # unexpected shape is rare + actionable — dump everything so we can see what telnyx sent.
    Logger.warning(
      "telnyx webhook with unexpected shape — ignoring. params=#{inspect(params, pretty: true, limit: :infinity, printable_limit: :infinity)}"
    )

    send_resp(conn, 200, "")
  end

  defp log_full_payload(event_type, data) do
    Logger.debug("""
    telnyx webhook payload: #{event_type}
    #{inspect(data, pretty: true, limit: :infinity, printable_limit: :infinity)}\
    """)
  end

  defp handle_event("call.initiated", %{"call_control_id" => ccid, "to" => to} = payload) do
    cond do
      EllieAi.Drain.draining?() ->
        Logger.warning("call.initiated rejected: container is draining ccid=#{ccid}")
        # don't answer — caller hears telnyx's natural ring-out / failover.
        :ok

      true ->
        do_call_initiated(ccid, to, payload)
    end
  end

  defp handle_event("call.answered", %{"call_control_id" => ccid}) do
    # staff legs the escalator dialed get bridged back to the caller — no streaming on them.
    case EllieAi.Calls.Escalator.on_staff_answered(ccid) do
      :ok ->
        if EllieAi.Calls.Escalator.escalation_leg?(ccid) do
          :ok
        else
          stream_url = media_streaming_url()
          Logger.info("call.answered ccid=#{ccid} → streaming_start to #{stream_url}")
          Calls.record_system_event(ccid, "telnyx", "telnyx.call.answered", "Call answered", nil)
          Client.streaming_start(ccid, stream_url)
        end

      _ ->
        :ok
    end
  end

  defp handle_event("call.hangup", %{"call_control_id" => ccid} = payload) do
    Logger.info("call.hangup ccid=#{ccid}")
    Calls.record_system_event(ccid, "telnyx", "telnyx.call.hangup", "Call hung up", payload)
    Calls.on_hangup(ccid)
  end

  defp handle_event(other, _payload) do
    Logger.debug("telnyx webhook event ignored: #{other}")
    :ok
  end

  defp do_call_initiated(ccid, to, payload) do
    case Orgs.get_by_telnyx_number(to) do
      nil ->
        Logger.warning(
          "telnyx call to #{to} but no org has that number provisioned — rejecting"
        )

        # no Client.reject yet — rejecting inbound is v0+1. telnyx times out into its default failover.
        :ok

      org ->
        # canonicalize From at the boundary. SIP relays (esp. Google Voice) send things like
        # `+1442070817673@152.189.4.248:5060` — SIP-suffixed and prefix-mangled. Phones.to_e164
        # strips the suffix, retries without the spurious +1, then falls back through GB/AU/IN/CA.
        # on failure we keep the raw string so staff can still see the unparseable value.
        from_canonical =
          case EllieAi.Phones.to_e164(payload["from"]) do
            {:ok, e164} ->
              e164

            {:error, reason} ->
              Logger.warning(
                "call.initiated: could not normalize From=#{inspect(payload["from"])} (#{inspect(reason)}); storing raw"
              )

              EllieAi.Phones.clean(payload["from"])
          end

        payload = Map.put(payload, "from", from_canonical)
        Logger.info("call.initiated for org=#{org.slug} ccid=#{ccid} from=#{payload["from"]}")

        case Calls.spawn_or_noop(org, ccid, payload) do
          {:ok, _pid} ->
            Calls.record_system_event(
              ccid,
              "telnyx",
              "telnyx.call.initiated",
              "Call from #{payload["from"]} to #{to}",
              payload
            )

            Client.answer(ccid)

          {:error, reason} ->
            Logger.error("could not start call tree: #{inspect(reason)}")
        end
    end
  end

  # dev uses the ngrok url written into root .env by `mise run dev`; prod uses PHX_HOST.
  defp media_streaming_url do
    base =
      System.get_env("NGROK_URL") ||
        Application.get_env(:ellie_ai, :public_url) ||
        "https://example.com"

    base
    |> String.replace_prefix("https://", "wss://")
    |> String.replace_prefix("http://", "ws://")
    |> Kernel.<>("/telnyx/media-streaming")
  end
end
