defmodule EllieAi.Providers.OpenAI do
  @moduledoc "openai provider — realtime + chat config readers."

  require Logger

  @default_realtime_model "gpt-realtime-2025-08-28"
  @default_voice "alloy"
  @default_transcription_model "whisper-1"
  @default_chat_model "gpt-4o-mini"
  @default_base_url "https://api.openai.com"

  def realtime_model do
    System.get_env("OPENAI_REALTIME_MODEL") ||
      config(:realtime_model, @default_realtime_model)
  end

  def voice, do: config(:voice, @default_voice)

  # fixed at g711_ulaw to match telnyx's wire format 1:1.
  def audio_format, do: "g711_ulaw"

  def transcription_model, do: config(:transcription_model, @default_transcription_model)

  def realtime_ws_url do
    "wss://api.openai.com/v1/realtime?model=#{realtime_model()}"
  end

  # no `OpenAI-Beta` header — GA realtime rejects `realtime=v1` as `invalid_beta`.
  def realtime_ws_headers do
    case api_key() do
      key when is_binary(key) and key != "" ->
        {:ok, [{"Authorization", "Bearer #{key}"}]}

      _ ->
        {:error, :openai_api_key_missing}
    end
  end

  def connect_info do
    case realtime_ws_headers() do
      {:ok, headers} -> {:ok, realtime_ws_url(), headers}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec chat([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(messages, opts \\ []) when is_list(messages) do
    case api_key() do
      nil ->
        {:error, :no_api_key}

      key ->
        body = build_chat_body(messages, opts)
        url = "#{base_url()}/v1/chat/completions"

        case Req.post(url,
               json: body,
               auth: {:bearer, key},
               receive_timeout: Keyword.get(opts, :receive_timeout, 5_000),
               retry: :transient,
               max_retries: Keyword.get(opts, :max_retries, 2)
             ) do
          {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
            {:ok, content}

          {:ok, %{status: status, body: body}} ->
            {:error, {:http, status, body}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp build_chat_body(messages, opts) do
    base = %{
      model: Keyword.get(opts, :model, @default_chat_model),
      messages: messages,
      temperature: Keyword.get(opts, :temperature, 0)
    }

    case Keyword.get(opts, :response_format) do
      nil -> base
      fmt -> Map.put(base, :response_format, fmt)
    end
  end

  defp api_key, do: System.get_env("OPENAI_API_KEY")

  defp base_url, do: config(:base_url, @default_base_url)

  defp config(key, default) do
    Application.get_env(:ellie_ai, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
