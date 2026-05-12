defmodule EllieAiWeb.TelnyxMessageWebhookController do
  @moduledoc """
  inbound telnyx sms webhooks. signature is verified upstream by
  `EllieAi.Telnyx.SignaturePlug`. v1 only handles `message.received`;
  delivery receipts are 200'd and ignored. dedup via `Calls.SmsDedup`
  (5-minute ETS cache) absorbs telnyx's retry-on-non-2xx behaviour.
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
    # `message.sent` / `message.finalized` etc. — log and drop until we surface delivery status in the UI.
    Logger.debug("telnyx sms webhook: ignoring event=#{other}")
    :ok
  end

  defp ingest_received(message_id, payload) do
    text = payload["text"] || ""
    raw_from = get_in(payload, ["from", "phone_number"])
    raw_to = first_to_number(payload["to"])

    # canonicalize at the boundary, same shape as call.initiated. matches
    # whatever calls.from_phone was stamped with so channel_id lookups
    # collide on the right row.
    from = normalize(raw_from)
    to = normalize(raw_to)

    with {:ok, org} <- resolve_org(to),
         from when is_binary(from) <- from,
         {:ok, _turn} <- Calls.ingest_inbound_sms(org.id, from, text, to) do
      Logger.info("sms ingested id=#{message_id} from=#{from} to=#{to}")
      :ok
    else
      {:error, :no_parent_call} ->
        # already logged inside Calls.ingest_inbound_sms/4
        :ok

      {:error, reason} ->
        Logger.warning("sms ingest failed id=#{message_id} reason=#{inspect(reason)}")
        :ok

      nil ->
        Logger.warning(
          "sms ingest dropped id=#{message_id}: missing from.phone_number (raw=#{inspect(raw_from)})"
        )

        :ok
    end
  end

  # phone normalization at the SMS webhook boundary. on failure we keep
  # the cleaned raw so resolve_org / channel_id can still try a match —
  # better to attempt the lookup than drop the message because of a parse
  # gripe.
  defp normalize(nil), do: nil

  defp normalize(raw) do
    case EllieAi.Phones.to_e164(raw) do
      {:ok, e164} ->
        e164

      {:error, reason} ->
        Logger.warning("sms normalize: #{inspect(raw)} → #{inspect(reason)}; using cleaned raw")
        EllieAi.Phones.clean(raw)
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
