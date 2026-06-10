defmodule EllieAi.Calls.FraudResponder do
  @moduledoc """
  on a fraud threshold breach:

    1. hang up the scammer leg immediately,
    2. dial the configured operator number,
    3. speak a short summary on the alert leg once it answers.

  modeled on `EllieAi.Calls.Escalator` — same ETS pairing pattern. v1
  scope: env var phone, no per-org settings, no DTMF interactive flow.
  """

  alias EllieAi.Calls
  alias EllieAi.Telnyx.Client, as: TC

  require Logger

  @table :ellie_fraud_alert_legs

  @doc "fire-and-forget. hangs up the scammer leg, dials the user, registers the summary."
  @spec trigger(String.t(), String.t()) :: :ok | {:error, term()}
  def trigger(scammer_ccid, summary) when is_binary(scammer_ccid) and is_binary(summary) do
    Logger.warning("fraud_responder triggered for ccid=#{scammer_ccid}: #{summary}")

    Calls.record_system_event(
      scammer_ccid,
      "fraud_responder",
      "fraud_responder.triggered",
      summary,
      nil
    )

    # 1. drop the scammer leg first so the victim is no longer on a live scam call.
    case TC.hangup(scammer_ccid) do
      :ok ->
        Calls.record_system_event(
          scammer_ccid,
          "fraud_responder",
          "fraud_responder.scammer_hangup",
          "Scammer leg hung up",
          nil
        )

      {:error, reason} ->
        Logger.warning(
          "fraud_responder: scammer hangup failed ccid=#{scammer_ccid} reason=#{inspect(reason)}"
        )
    end

    # 2. dial the user (operator) and queue the summary for when they pick up.
    with {:ok, to} <- alert_phone(),
         {:ok, from} <- alert_from_number(),
         connection_id when is_binary(connection_id) <- telnyx_connection_id(),
         webhook_url when is_binary(webhook_url) <- webhook_url(),
         {:ok, alert_ccid} <- TC.dial(connection_id, to, from, webhook_url) do
      remember_alert(alert_ccid, summary, scammer_ccid)

      Calls.record_system_event(
        scammer_ccid,
        "fraud_responder",
        "fraud_responder.alert_dialing",
        "Dialing operator at #{to}",
        %{alert_ccid: alert_ccid}
      )

      :ok
    else
      {:error, reason} = err ->
        Logger.warning("fraud_responder: alert dial failed: #{inspect(reason)}")

        Calls.record_system_event(
          scammer_ccid,
          "fraud_responder",
          "fraud_responder.alert_failed",
          "Could not dial operator: #{inspect(reason)}",
          nil
        )

        err

      nil ->
        Logger.warning("fraud_responder: missing telnyx config (connection_id/from/webhook)")
        {:error, {:permanent, "telnyx alert not configured"}}
    end
  end

  @doc "webhook handler dispatch: speak the summary on the alert leg."
  @spec on_alert_answered(String.t()) :: :ok | {:error, term()}
  def on_alert_answered(alert_ccid) when is_binary(alert_ccid) do
    case lookup_alert(alert_ccid) do
      nil ->
        :ok

      %{summary: summary, scammer_ccid: scammer_ccid} ->
        Calls.record_system_event(
          scammer_ccid,
          "fraud_responder",
          "fraud_responder.alert_answered",
          "Operator picked up",
          %{alert_ccid: alert_ccid}
        )

        case TC.speak(alert_ccid, full_alert_text(summary)) do
          :ok ->
            Calls.record_system_event(
              scammer_ccid,
              "fraud_responder",
              "fraud_responder.alert_spoken",
              "Spoken summary delivered to operator",
              nil
            )

            :ok

          {:error, reason} = err ->
            Logger.warning(
              "fraud_responder: speak failed alert_ccid=#{alert_ccid} reason=#{inspect(reason)}"
            )

            Calls.record_system_event(
              scammer_ccid,
              "fraud_responder",
              "fraud_responder.speak_failed",
              "Speak failed: #{inspect(reason)}",
              nil
            )

            err
        end
    end
  end

  @doc "true if this ccid is an alert leg we dialed."
  @spec alert_leg?(String.t()) :: boolean()
  def alert_leg?(ccid) when is_binary(ccid) do
    ensure_table()
    :ets.member(@table, ccid)
  end

  # ── ETS pairing ───────────────────────────────────────────────────────

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end
  end

  defp remember_alert(alert_ccid, summary, scammer_ccid) do
    ensure_table()
    :ets.insert(@table, {alert_ccid, %{summary: summary, scammer_ccid: scammer_ccid}})
    :ok
  end

  defp lookup_alert(alert_ccid) do
    ensure_table()

    case :ets.lookup(@table, alert_ccid) do
      [{^alert_ccid, info}] -> info
      [] -> nil
    end
  end

  # ── config ────────────────────────────────────────────────────────────

  defp alert_phone do
    case System.get_env("FRAUD_ALERT_PHONE_E164") do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:permanent, "FRAUD_ALERT_PHONE_E164 not set"}}
    end
  end

  defp alert_from_number do
    case System.get_env("ELLIE_TELNYX_FROM") do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:permanent, "ELLIE_TELNYX_FROM not set for outbound alert"}}
    end
  end

  defp telnyx_connection_id, do: System.get_env("TELNYX_CONNECTION_ID")

  defp webhook_url do
    System.get_env("NGROK_URL") ||
      Application.get_env(:ellie_ai, :public_url) ||
      System.get_env("PUBLIC_URL")
  end

  defp full_alert_text(summary) do
    "Fraud detection alert. " <>
      summary <>
      " The suspicious call has been ended. End of alert."
  end
end
