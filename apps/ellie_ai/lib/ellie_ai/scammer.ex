defmodule EllieAi.Scammer do
  @moduledoc """
  outbound scammer-AI dialer for the fraud-detection prototype.

  this module places an outbound Telnyx call to a target number,
  registers the new ccid as a "scammer leg" with a chosen script, and
  spawns the standard `CallTree` for it. when the user picks up
  (`call.answered` webhook) the existing media-streaming path runs as
  normal — the scammer prompt + voice come from Memory, populated here.

  the scammer is NOT bridged with anything. it runs as a single AI
  speaker on the outbound leg, talking directly to the user.

  `EllieAi.Calls.FraudDetector` side-listens on the same transcript and
  fires `FraudResponder.trigger/2` when it crosses threshold — that
  hangs up this leg and dials the user back on a separate alert leg.
  """

  alias EllieAi.{Calls, Orgs}
  alias EllieAi.Calls.Memory
  alias EllieAi.Scammer.Scripts
  alias EllieAi.Scammer.Scripts.Script
  alias EllieAi.Telnyx.Client, as: TC

  require Logger

  @table :ellie_scammer_legs

  @doc """
  place an outbound call to `to_e164` running `script_id`. returns
  `{:ok, ccid}` on dial success.
  """
  @spec dial(String.t(), atom()) :: {:ok, String.t()} | {:error, term()}
  def dial(to_e164, script_id) when is_binary(to_e164) and is_atom(script_id) do
    with %Script{} = script <- Scripts.fetch!(script_id),
         :ok <- ensure_backend_available(script),
         {:ok, from} <- from_number(),
         connection_id when is_binary(connection_id) <- connection_id(),
         webhook_url when is_binary(webhook_url) <- webhook_url(),
         %_{} = org <- default_org(),
         {:ok, ccid} <- TC.dial(connection_id, to_e164, from, webhook_url) do
      Logger.info(
        "scammer dial started: ccid=#{ccid} to=#{to_e164} script=#{script_id} backend=#{script.backend}"
      )

      remember_leg(ccid, script_id)

      # spawn CallTree now so Memory is populated and AudioBridge is
      # ready to take the media stream the instant call.answered fires.
      case Calls.spawn_or_noop(org, ccid, %{"from" => from, "to" => to_e164, "scammer" => true}) do
        {:ok, _pid} ->
          install_scammer_context(ccid, script)

          Calls.record_system_event(
            ccid,
            "scammer",
            "scammer.dialing",
            "Outbound scammer dial to #{to_e164} (script=#{script_id})",
            %{script: to_string(script_id), backend: to_string(script.backend)}
          )

          {:ok, ccid}

        {:error, reason} = err ->
          Logger.error("scammer: could not spawn call tree ccid=#{ccid}: #{inspect(reason)}")
          err
      end
    else
      {:error, reason} = err ->
        Logger.warning("scammer dial failed: #{inspect(reason)}")
        err

      nil ->
        Logger.warning("scammer dial missing config (connection_id/from/webhook/org)")
        {:error, {:permanent, "scammer not configured"}}
    end
  end

  @doc "true if this ccid was dialed by the scammer."
  @spec scammer_leg?(String.t()) :: boolean()
  def scammer_leg?(ccid) when is_binary(ccid) do
    ensure_table()
    :ets.member(@table, ccid)
  end

  @doc "script id bound to this scammer leg, or nil if unknown."
  @spec script_for(String.t()) :: atom() | nil
  def script_for(ccid) when is_binary(ccid) do
    ensure_table()

    case :ets.lookup(@table, ccid) do
      [{^ccid, script_id}] -> script_id
      [] -> nil
    end
  end

  # ── internals ─────────────────────────────────────────────────────────

  defp ensure_backend_available(%Script{backend: :realtime}), do: :ok

  defp ensure_backend_available(%Script{backend: :modular, id: id}) do
    Logger.warning(
      "scammer: script #{id} uses :modular backend; not implemented in v1 (KugelAudio adapter pending)"
    )

    {:error, {:permanent, "modular backend not implemented in v1 (script=#{id})"}}
  end

  defp install_scammer_context(ccid, %Script{} = script) do
    # overwrite the org-templated rendered_prompt with the scammer
    # persona. `Memory.scammer_script/1` is set so `Prompts.re_render!`
    # doesn't clobber us on the next turn.
    Memory.put_call_context(ccid, %{
      rendered_prompt: bake_prompt(script),
      realtime_voice: script.voice,
      scammer_script: script.id
    })
  end

  defp bake_prompt(%Script{system_prompt: body, opening_line: opener}) do
    """
    #{body}

    OPENING — your very first turn must begin with this exact sentence (delivered in the persona voice; you may add a brief natural opener like "um, hi —" if it fits):

      "#{opener}"
    """
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end
  end

  defp remember_leg(ccid, script_id) do
    ensure_table()
    :ets.insert(@table, {ccid, script_id})
    :ok
  end

  # ── config ────────────────────────────────────────────────────────────

  defp from_number do
    case System.get_env("ELLIE_TELNYX_FROM") do
      v when is_binary(v) and v != "" ->
        {:ok, v}

      _ ->
        # fall back to first org's telnyx number — convenient in dev.
        case default_org() do
          %_{telnyx_phone_number: v} when is_binary(v) and v != "" -> {:ok, v}
          _ -> {:error, {:permanent, "no outbound `from` number (set ELLIE_TELNYX_FROM)"}}
        end
    end
  end

  defp connection_id, do: System.get_env("TELNYX_CONNECTION_ID")

  defp webhook_url do
    System.get_env("NGROK_URL") ||
      Application.get_env(:ellie_ai, :public_url) ||
      System.get_env("PUBLIC_URL")
  end

  # any org works — we just need its id to write the Call row and
  # bootstrap Memory. prototype is single-tenant.
  defp default_org do
    case Orgs.list() do
      [org | _] -> org
      _ -> nil
    end
  end
end
