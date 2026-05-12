defmodule EllieAiWeb.TelnyxWebhookController do
  @moduledoc """
  inbound webhook from telnyx. signature is already verified by the
  pipeline plug — by the time we get here, the body is trustworthy.

  the events we care about for v0:

    * `call.initiated` — telnyx asks us whether to answer. we look up the
      org by dialed number, ack, and tell telnyx to answer the call.
    * `call.answered` — telnyx confirms the leg is up. we kick off media
      streaming (telnyx connects back to our wss:// endpoint with audio).
    * `call.hangup`   — caller (or we) ended the call. tear down state.

  every other event is logged and 200'd so telnyx doesn't retry forever.

  ⚠️ idempotency: telnyx retries webhooks on non-2xx and may double-deliver
  on flaky networks. spawning the call tree is gated by a registry lookup
  inside `EllieAi.Calls.spawn_or_noop/2` (see plan OV-4) — duplicate
  call.initiated events become 5-line no-ops, not duplicate sessions.
  """

  use EllieAiWeb, :controller

  alias EllieAi.{Calls, Orgs}
  alias EllieAi.Telnyx.Client

  require Logger

  @doc """
  single endpoint: POST /telnyx/webhook. telnyx wraps the actual event
  inside `data.event_type` + `data.payload`.
  """
  def handle(conn, %{"data" => %{"event_type" => event_type, "payload" => payload} = data}) do
    Logger.info("telnyx webhook: #{event_type}")
    log_full_payload(event_type, data)
    handle_event(event_type, payload)
    send_resp(conn, 200, "")
  end

  def handle(conn, params) do
    # unexpected shape IS rare + actionable — keep the full param dump
    # so we know exactly what telnyx sent us when this fires.
    Logger.warning(
      "telnyx webhook with unexpected shape — ignoring. params=#{inspect(params, pretty: true, limit: :infinity, printable_limit: :infinity)}"
    )

    send_resp(conn, 200, "")
  end

  # full-fidelity webhook log at :debug. info already shows the one-line
  # summary ("telnyx webhook: <event_type>"); this is the pretty-printed
  # `data` block (event_type + payload + metadata like `occurred_at`,
  # `record_type`). useful for diagnosing field-level questions ("did
  # telnyx echo our codec choice?", "what hangup_cause did we get?") —
  # flip Logger to :debug for the next call when you need it.
  defp log_full_payload(event_type, data) do
    Logger.debug("""
    telnyx webhook payload: #{event_type}
    #{inspect(data, pretty: true, limit: :infinity, printable_limit: :infinity)}\
    """)
  end

  # call.initiated arrives the instant a caller dials the telnyx number.
  # we resolve org by dialed number ("to"), then tell telnyx to answer.
  # everything from there flows through call.answered → streaming_start.
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

  # call.answered means the call leg is up and audio can flow. we kick
  # off bidirectional media streaming so telnyx connects back to our
  # wss:// endpoint. the stream URL is built from the public host (set
  # by mise's dev task to the ngrok https url, or by prod's PHX_HOST).
  defp handle_event("call.answered", %{"call_control_id" => ccid}) do
    # if this is a staff leg the escalator dialed, bridge it back to the
    # caller — no streaming on staff legs. on a real inbound caller leg
    # the escalator returns :ok (no pairing) and we fall through to the
    # normal streaming_start path.
    case EllieAi.Calls.Escalator.on_staff_answered(ccid) do
      :ok ->
        if EllieAi.Calls.Escalator.escalation_leg?(ccid) do
          # staff leg — don't open a media stream on it.
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

  # extracted from handle_event/2 so the drain wrapper stays small and all
  # handle_event clauses stay contiguous (no warning about ungrouped
  # function clauses).
  defp do_call_initiated(ccid, to, payload) do
    case Orgs.get_by_telnyx_number(to) do
      nil ->
        Logger.warning(
          "telnyx call to #{to} but no org has that number provisioned — rejecting"
        )

        # no Client.reject here yet — rejecting an inbound call is a v0+1
        # task. for now we just don't answer; telnyx will time out and
        # play its default failover. logged so it's visible in dev.
        :ok

      org ->
        Logger.info("call.initiated for org=#{org.slug} ccid=#{ccid} from=#{payload["from"]}")
        # spawn (or no-op) the per-call supervision tree, then tell
        # telnyx to answer. webhook retries → spawn_or_noop returns the
        # same pid, so this stays idempotent (plan OV-4).
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

  # build the wss:// URL telnyx connects to for media streaming. dev uses
  # the ngrok tunnel url that `mise run dev` writes back into root .env.
  # prod uses PHX_HOST.
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
