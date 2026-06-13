defmodule EllieAi.Calls.FraudDetector do
  @moduledoc """
  third-party AI side-listener for scammer/victim conversations.

  runs per finalized transcript turn (both roles) and combines two
  signals over the rolling transcript:

    * `Heuristics` — regex/keyword score (synchronous, cheap).
    * LLM — `Medium.Chat.generate` with a JSON-only system prompt; same
      shape `Sentiment` uses.

  combined score uses `max(heuristic, llm)`. crossing `fraud_threshold/0`
  fires `FraudResponder.trigger/2` exactly once per ccid (ETS dedupe).

  worker-rules from `apps/ellie_ai/AGENTS.md`: no `%Org{}` argument, no
  `alias EllieAi.Orgs.Org`. read context off `Memory.org/0`.

  extension point: `aggregate/1` accepts a list of `{name, score}` so a
  future `AudioFraudScorer` plugs in without rewriting the detector.
  """

  alias EllieAi.{Calls, Medium}
  alias EllieAi.Calls.{FraudDetector.Heuristics, FraudResponder, Memory, TranscriptTurn}

  require Logger

  @model "gpt-4o-mini"
  @default_threshold 0.7
  @table :ellie_fraud_detector_fired

  @doc """
  score every finalized turn — but only for scammer legs in v1 so the
  detector doesn't run (and pay an LLM call) on normal Ellie restaurant
  calls. fire-and-forget via Memory.async/1.
  """
  @spec analyze_async(TranscriptTurn.t()) :: :ok
  def analyze_async(%TranscriptTurn{text: text} = turn) when is_binary(text) do
    Memory.async(fn -> analyze_and_maybe_trigger(turn) end)
    :ok
  end

  def analyze_async(_), do: :ok

  @doc "current threshold from env, default #{@default_threshold}."
  @spec fraud_threshold() :: float()
  def fraud_threshold do
    case System.get_env("FRAUD_THRESHOLD") do
      nil ->
        @default_threshold

      v ->
        case Float.parse(v) do
          {f, _} -> f
          :error -> @default_threshold
        end
    end
  end

  @doc "combine an arbitrary list of `{name, score}` signals. `max` for v1."
  @spec aggregate([{atom(), float()}]) :: {float(), atom() | nil}
  def aggregate(signals) when is_list(signals) do
    case Enum.max_by(signals, fn {_n, s} -> s end, fn -> nil end) do
      nil -> {0.0, nil}
      {name, score} -> {score, name}
    end
  end

  # ── internals ─────────────────────────────────────────────────────────

  defp analyze_and_maybe_trigger(%TranscriptTurn{} = turn) do
    ccid = ccid_for_turn(turn)

    # v1 scope: only score scammer legs. normal restaurant calls skip
    # the detector entirely (no extra LLM cost, no FP risk for ellie).
    cond do
      not is_binary(ccid) ->
        :ok

      is_nil(Memory.scammer_script(ccid)) ->
        :ok

      already_fired?(ccid) ->
        :ok

      true ->
        do_analyze(ccid, turn)
    end
  end

  defp do_analyze(ccid, turn) do
    transcript = Memory.transcript(ccid)
    {heur_score, heur_labels} = Heuristics.score(transcript)

    # stop-test phrase is a hard override: skip the LLM, trigger now.
    if Heuristics.stop_test?(turn.text) do
      Logger.warning("fraud_detector: STOP TEST detected for ccid=#{ccid}")
      record_event(ccid, :operator_stop, 1.0, [:operator_stop], "operator STOP TEST")
      mark_fired(ccid)
      FraudResponder.trigger(ccid, "Operator stop received — call ended.")
    else
      llm_result = llm_score(transcript)
      signals = collect_signals(heur_score, llm_result)
      {combined, winner} = aggregate(signals)

      if combined >= fraud_threshold() do
        summary = build_summary(combined, winner, heur_labels, llm_result)
        record_event(ccid, winner || :unknown, combined, heur_labels, summary)
        mark_fired(ccid)
        FraudResponder.trigger(ccid, summary)
      else
        Logger.debug(
          "fraud_detector ccid=#{ccid} combined=#{Float.round(combined, 2)} below threshold"
        )
      end
    end
  end

  defp ccid_for_turn(%TranscriptTurn{}) do
    Memory.ccid()
  end

  defp ccid_for_turn(_), do: nil

  defp collect_signals(heur_score, {:ok, llm_score, _reason}) do
    [{:heuristics, heur_score}, {:llm, llm_score}]
  end

  defp collect_signals(heur_score, _) do
    [{:heuristics, heur_score}]
  end

  defp llm_score([]), do: {:error, :empty_transcript}

  defp llm_score(transcript) when is_list(transcript) do
    body = render_transcript(transcript)

    messages = [
      %{
        role: "system",
        content: """
        You are a fraud/scam call classifier. Read the conversation and return ONLY a JSON object:
        {"score": <float 0..1>, "reason": "<<=120 chars>"}
        - 0.0 means clearly benign (no scam markers)
        - 1.0 means clearly a phone scam (impersonation, payment-method tells, urgency, social engineering)
        Be cautious — only score >0.5 when there is real evidence in the conversation. No prose outside JSON.
        """
      },
      %{role: "user", content: body}
    ]

    case Medium.Chat.generate(messages,
           model: @model,
           response_format: %{type: "json_object"},
           receive_timeout: 5_000
         ) do
      {:ok, content} -> parse_llm_response(content)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_llm_response(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"score" => s} = m} when is_number(s) ->
        {:ok, clamp(s / 1), Map.get(m, "reason", "")}

      _ ->
        {:error, {:bad_response, content}}
    end
  end

  defp parse_llm_response(_), do: {:error, :bad_response}

  defp render_transcript(turns) do
    Enum.map_join(turns, "\n", fn
      {role, text, _at} -> "#{role}: #{text}"
      {role, text} -> "#{role}: #{text}"
    end)
  end

  defp clamp(s) when s < 0.0, do: 0.0
  defp clamp(s) when s > 1.0, do: 1.0
  defp clamp(s), do: s

  defp build_summary(score, winner, labels, {:ok, _llm_score, reason}) do
    "Fraud score #{Float.round(score, 2)} (#{winner}). " <>
      "Heuristics: #{labels_str(labels)}. " <>
      "Reason: #{reason}"
  end

  defp build_summary(score, winner, labels, _) do
    "Fraud score #{Float.round(score, 2)} (#{winner}). Heuristics: #{labels_str(labels)}."
  end

  defp labels_str([]), do: "(none)"
  defp labels_str(labels), do: labels |> Enum.map(&to_string/1) |> Enum.join(", ")

  defp record_event(ccid, winner, score, labels, summary) do
    Calls.record_system_event(
      ccid,
      "fraud_detector",
      "fraud_detector.threshold_breached",
      "Fraud detected (#{winner}, #{Float.round(score, 2)})",
      %{score: score, winner: winner, labels: labels, summary: summary}
    )
  end

  # ── ETS dedupe ────────────────────────────────────────────────────────

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end
  end

  defp already_fired?(ccid) do
    ensure_table()
    :ets.member(@table, ccid)
  end

  defp mark_fired(ccid) do
    ensure_table()
    :ets.insert(@table, {ccid, DateTime.utc_now()})
    :ok
  end
end
