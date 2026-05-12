defmodule EllieAiWeb.TelnyxMessageWebhookController do
  @moduledoc """
  inbound webhook for telnyx sms (message.received + delivery receipts).
  signature is verified by the same `EllieAi.Telnyx.SignaturePlug`
  pipeline as call webhooks — by the time we get here, the body is
  trustworthy.

  v1 only cares about `message.received`. delivery receipts (sent /
  finalized) are 200'd and ignored — we don't track per-message status
  in the UI yet.

  dedup: telnyx retries webhooks on non-2xx. we keep a 5-minute ETS
  cache of message ids we've already inserted (see `Calls.SmsDedup`).
  retries that land within the TTL become no-ops.
  """

  use EllieAiWeb, :controller

  alias EllieAi.{Calls, Orgs}
  alias EllieAi.Calls.SmsDedup

  require Logger

  def handle(conn, %{"data" => %{"event_type" => event_type, "payload" => payload}}) do
    Logger.info("telnyx sms webhook: #{event_type}")
    handle_event(event_type, payload)
    send_resp(conn, 200, "")
  end

  def handle(conn, params) do
    Logger.warning(
      "telnyx sms webhook with unexpected shape — ignoring. params=#{inspect(params, pretty: true, limit: :infinity)}"
    )

    send_resp(conn, 200, "")
  end

  defp handle_event("message.received", %{"id" => message_id} = payload) do
    case SmsDedup.see(message_id) do
      :duplicate ->
        Logger.info("sms dedup: dropped retry of #{message_id}")
        :ok

      :fresh ->
        ingest_received(message_id, payload)
    end
  end

  defp handle_event(other, _payload) do
    # `message.sent` / `message.finalized` etc. — log and drop. when we
    # surface delivery status in the UI we'll grow handlers for these.
    Logger.debug("telnyx sms webhook: ignoring event=#{other}")
    :ok
  end

  defp ingest_received(message_id, payload) do
    text = payload["text"] || ""
    from = get_in(payload, ["from", "phone_number"])
    to = first_to_number(payload["to"])

    with {:ok, org} <- resolve_org(to),
         from when is_binary(from) <- from,
         {:ok, _turn} <- Calls.ingest_inbound_sms(org.id, from, text, to) do
      Logger.info("sms ingested id=#{message_id} from=#{from} to=#{to}")
      :ok
    else
      {:error, :no_parent_call} ->
        # already logged inside Calls.ingest_inbound_sms/3
        :ok

      {:error, reason} ->
        Logger.warning("sms ingest failed id=#{message_id} reason=#{inspect(reason)}")
        :ok

      nil ->
        Logger.warning("sms ingest dropped id=#{message_id}: missing from.phone_number")
        :ok
    end
  end

  defp first_to_number([%{"phone_number" => n} | _]), do: n
  defp first_to_number(_), do: nil

  defp resolve_org(nil), do: {:error, :no_to_number}

  defp resolve_org(phone) when is_binary(phone) do
    case Orgs.get_by_telnyx_number(phone) do
      nil -> {:error, {:no_org_for_number, phone}}
      org -> {:ok, org}
    end
  end
end
