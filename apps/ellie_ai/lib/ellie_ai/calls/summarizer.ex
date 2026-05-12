defmodule EllieAi.Calls.Summarizer do
  @moduledoc """
  post-call one-sentence summary (gpt-4o-mini). fire-and-forget; failures
  log and move on. lands on calls.summary; UI shows it on /customers/:id.
  """

  alias EllieAi.{Calls, Medium, Repo}
  alias EllieAi.Calls.{Call, TranscriptTurn}

  import Ecto.Query

  require Logger

  @model "gpt-4o-mini"
  @max_chars 240

  @spec summarize_async(Ecto.UUID.t()) :: :ok
  def summarize_async(call_id) when is_binary(call_id) do
    Task.start(fn -> summarize(call_id) end)
    :ok
  end

  defp summarize(call_id) do
    started = System.monotonic_time(:millisecond)

    with %Call{} = call <- Repo.get(Call, call_id),
         turns when turns != [] <- load_turns(call_id),
         {:ok, text} <- fetch_summary(call, turns) do
      dur = System.monotonic_time(:millisecond) - started
      Logger.info("summarizer #{@model} → #{dur}ms call_id=#{call_id} text=#{inspect(text)}")
      Calls.set_summary(call_id, text)
    else
      nil ->
        Logger.info("summarizer: no call row for #{call_id}")

      [] ->
        Logger.info("summarizer: no turns for call_id=#{call_id}, skipping")

      {:error, reason} ->
        Logger.warning("summarizer failed call_id=#{call_id}: #{inspect(reason)}")
    end
  end

  defp load_turns(call_id) do
    from(t in TranscriptTurn,
      where: t.call_id == ^call_id,
      order_by: [asc: t.inserted_at],
      limit: 200
    )
    |> Repo.all()
  end

  defp fetch_summary(%Call{} = call, turns) do
    transcript = render_transcript(turns)

    messages = [
      %{
        role: "system",
        content:
          "You summarize a restaurant phone call in one short sentence " <>
            "(max #{@max_chars} characters). Focus on the outcome — what " <>
            "did the caller want, what happened? Plain prose, no quotes, no preamble."
      },
      %{role: "user", content: render_call_context(call) <> "\n\n" <> transcript}
    ]

    case Medium.Chat.generate(messages,
           model: @model,
           temperature: 0.2,
           receive_timeout: 8_000
         ) do
      {:ok, content} ->
        {:ok, content |> to_string() |> String.trim() |> String.slice(0, @max_chars)}

      {:error, _} = err ->
        err
    end
  end

  defp render_call_context(%Call{} = call) do
    parts = [
      call.from_phone && "from: #{call.from_phone}",
      call.to_phone && "to: #{call.to_phone}",
      call.hangup_reason && "hangup_reason: #{call.hangup_reason}",
      call.status && "status: #{call.status}"
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp render_transcript(turns) do
    turns
    |> Enum.map(fn t -> "#{t.role} (#{t.medium}): #{t.text}" end)
    |> Enum.join("\n")
  end
end
