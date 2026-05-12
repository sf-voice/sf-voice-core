defmodule EllieAi.Calls.Escalator do
  @moduledoc """
  hand a call from ai to human via telnyx: dial staff → bridge legs on
  `call.answered` → mark escalated. best-effort; no voicemail in v1.
  staff number from org's `staff_phone_e164` setting or env fallback.
  """

  alias EllieAi.Calls
  alias EllieAi.Orgs.Org
  alias EllieAi.Telnyx.Client

  require Logger

  @doc "kick off escalation. fire-and-forget; bridge happens on staff's call.answered webhook."
  @spec escalate(Org.t(), String.t()) :: :ok | {:error, term()}
  def escalate(%Org{} = org, ccid) when is_binary(ccid) do
    with {:ok, staff_to} <- staff_phone(org),
         {:ok, from} <- ellie_from_number(org),
         connection_id when is_binary(connection_id) <- telnyx_connection_id(),
         webhook_url when is_binary(webhook_url) <- webhook_url(),
         {:ok, staff_ccid} <- Client.dial(connection_id, staff_to, from, webhook_url) do
      Logger.info("escalation dial started: ccid=#{ccid} staff_ccid=#{staff_ccid} to=#{staff_to}")

      Calls.record_system_event(
        ccid,
        "escalator",
        "escalator.dialing",
        "Dialing staff at #{staff_to}",
        %{staff_ccid: staff_ccid}
      )

      remember_pairing(ccid, staff_ccid)
      :ok
    else
      {:error, reason} = err ->
        Logger.warning("escalation could not start: ccid=#{ccid} reason=#{inspect(reason)}")

        Calls.record_system_event(
          ccid,
          "escalator",
          "escalator.dial_failed",
          "Could not dial staff: #{inspect(reason)}",
          nil
        )

        err

      nil ->
        Logger.warning("escalation missing telnyx config (connection_id / from / webhook_url)")
        {:error, {:permanent, "telnyx escalation not configured"}}
    end
  end

  @doc "resolve the caller leg paired with this staff leg, then bridge them."
  @spec on_staff_answered(String.t()) :: :ok | {:error, term()}
  def on_staff_answered(staff_ccid) when is_binary(staff_ccid) do
    case lookup_pairing(staff_ccid) do
      nil ->
        # not an escalation leg — let normal flow handle it.
        :ok

      caller_ccid ->
        Calls.record_system_event(
          caller_ccid,
          "escalator",
          "escalator.staff_answered",
          "Staff picked up; bridging",
          %{staff_ccid: staff_ccid}
        )

        case Client.bridge(caller_ccid, staff_ccid) do
          :ok ->
            Calls.update_status(caller_ccid, EllieAi.Calls.Constants.status_escalated())

            Calls.record_system_event(
              caller_ccid,
              "escalator",
              "escalator.bridged",
              "Caller bridged with staff",
              nil
            )

            :ok

          {:error, reason} = err ->
            Calls.record_system_event(
              caller_ccid,
              "escalator",
              "escalator.bridge_failed",
              "Bridge failed: #{inspect(reason)}",
              nil
            )

            err
        end
    end
  end

  # vm-local pairings — escalations are seconds-long, v1 doesn't survive crashes.
  @table :ellie_escalator_pairings

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end
  end

  defp remember_pairing(caller_ccid, staff_ccid) do
    ensure_table()
    :ets.insert(@table, {staff_ccid, caller_ccid})
  end

  defp lookup_pairing(staff_ccid) do
    ensure_table()

    case :ets.lookup(@table, staff_ccid) do
      [{^staff_ccid, caller}] -> caller
      [] -> nil
    end
  end

  @doc "true if this ccid is a staff leg we dialed for escalation."
  @spec escalation_leg?(String.t()) :: boolean()
  def escalation_leg?(ccid) when is_binary(ccid) do
    ensure_table()
    :ets.member(@table, ccid)
  end

  defp staff_phone(%Org{id: org_id}) do
    case EllieAi.Settings.get_value(org_id, "staff_phone_e164", System.get_env("STAFF_PHONE_E164")) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:permanent, "no staff phone configured for this org"}}
    end
  end

  defp ellie_from_number(%Org{telnyx_phone_number: from}) when is_binary(from) and from != "",
    do: {:ok, from}

  defp ellie_from_number(_), do: {:error, {:permanent, "no telnyx number for org"}}

  defp telnyx_connection_id do
    System.get_env("TELNYX_CONNECTION_ID")
  end

  defp webhook_url do
    System.get_env("NGROK_URL") ||
      Application.get_env(:ellie_ai, :public_url) ||
      System.get_env("PUBLIC_URL")
  end
end
