defmodule EllieAi.Calls.Sentiment do
  @moduledoc """
  per-turn sentiment scoring with gpt-4o-mini. user transcript turns
  get scored asynchronously; the score lands on `transcript_turns.sentiment_score`
  (0.0 = very negative, 1.0 = very positive). the rolling call-level
  EMA lives on `calls.sentiment_score`; when it drops below the
  threshold (per-org `sentiment_threshold` setting, default 0.3), we
  fire off an escalation.

  the design review picked 0.3 as a placeholder. operators can tune
  per-org via the /settings UI without redeploying.

  scoring is fire-and-forget — failed requests log and move on rather
  than letting model drift block the call.
  """

  import Ecto.Query

  alias EllieAi.{Calls, Medium, Repo}
  alias EllieAi.Calls.{Call, Escalator, Memory, TranscriptTurn}

  require Logger

  @model "gpt-4o-mini"
  @ema_alpha 0.4

  @doc "default EMA threshold for auto-escalation when no per-org setting exists. 0.0–1.0."
  def default_threshold, do: 0.3

  @doc """
  fire-and-forget scoring of one transcript turn. reads org context from
  `Flag` (set up by the calling process — typically AudioBridge), and
  propagates that context into the spawned task so escalation calls can
  also read `Memory.staff_phone/0` etc.
  """
  @spec score_async(TranscriptTurn.t()) :: :ok
  def score_async(%TranscriptTurn{role: "user"} = turn) do
    Memory.async(fn -> score_and_persist(turn) end)
    :ok
  end

  # only score user turns. the assistant's tone is constrained by the
  # prompt; scoring it would just measure how well we follow the
  # template, not how the caller feels.
  def score_async(_turn), do: :ok

  defp score_and_persist(%TranscriptTurn{} = turn) do
    started = System.monotonic_time(:millisecond)

    case fetch_score(turn.text) do
      {:ok, score} ->
        dur = System.monotonic_time(:millisecond) - started

        Logger.info(
          "sentiment #{@model} → score=#{Float.round(score, 2)} in #{dur}ms " <>
            "text=#{inspect(String.slice(turn.text, 0, 80))}"
        )

        update_turn(turn, score)
        new_ema = update_call_ema(turn.call_id, score)
        maybe_escalate(turn.call_id, new_ema)

      {:error, reason} ->
        Logger.warning("sentiment scoring failed: #{inspect(reason)}")
    end
  end

  defp update_turn(turn, score) do
    turn
    |> TranscriptTurn.changeset(%{sentiment_score: score})
    |> Repo.update()
  end

  # exponential moving average so a single grumpy line doesn't trip
  # escalation, but a sustained drop does. the update is one atomic
  # sql statement so two concurrent user turns can't read the same
  # prior and clobber each other's contribution — the second turn
  # reads the value the first turn just wrote. read-back is a separate
  # statement; if a third turn lands between the update and the read,
  # we just see its (also valid) ema.
  defp update_call_ema(call_id, latest_score) do
    alpha = @ema_alpha
    one_minus_alpha = 1 - @ema_alpha

    query =
      from(c in Call,
        where: c.id == ^call_id,
        update: [
          set: [
            sentiment_score:
              fragment(
                "? * ? + ? * COALESCE(?, ?)",
                ^alpha,
                ^latest_score,
                ^one_minus_alpha,
                c.sentiment_score,
                ^latest_score
              )
          ]
        ]
      )

    case Repo.update_all(query, []) do
      {1, _} -> Repo.get(Call, call_id) |> Map.get(:sentiment_score)
      {0, _} -> nil
    end
  end

  defp maybe_escalate(_call_id, nil), do: :ok

  defp maybe_escalate(call_id, ema) when is_number(ema) do
    threshold = Memory.sentiment_threshold()

    if ema < threshold do
      case {Memory.org(), Repo.get(Call, call_id)} do
        {%_{} = org, %Call{provider_id: ccid, status: status}} when status != "escalated" ->
          Logger.info("sentiment dropped to #{ema} (< #{threshold}) — auto-escalating ccid=#{ccid}")

          Calls.record_system_event(
            ccid,
            "sentiment",
            "sentiment.threshold_breached",
            "EMA #{Float.round(ema, 2)} below #{threshold}",
            %{ema: ema, threshold: threshold}
          )

          Escalator.escalate(org, ccid)

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp fetch_score(text) when is_binary(text) do
    messages = [
      %{
        role: "system",
        content:
          "Return ONLY a JSON object {\"score\": <float 0..1>} where 0 is very negative and 1 is very positive. No prose."
      },
      %{role: "user", content: text}
    ]

    case Medium.Chat.generate(messages,
           model: @model,
           response_format: %{type: "json_object"},
           receive_timeout: 5_000
         ) do
      {:ok, content} -> parse_score(content)
      {:error, _} = err -> err
    end
  end

  defp parse_score(content) do
    with {:ok, %{"score" => score}} <- Jason.decode(content),
         true <- is_number(score) do
      {:ok, clamp(score / 1)}
    else
      _ -> {:error, {:bad_score_response, content}}
    end
  end

  defp clamp(s) when s < 0.0, do: 0.0
  defp clamp(s) when s > 1.0, do: 1.0
  defp clamp(s), do: s
end
