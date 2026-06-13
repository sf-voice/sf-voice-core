defmodule EllieAi.Telnyx.Client do
  @moduledoc """
  thin http wrapper for the telnyx call control api. config (base_url,
  api_key) comes from app env; dev/test fall back to a placeholder key so
  unit tests don't need real credentials. retry policy is req's
  `retry: :transient` — 4xx is permanent, 5xx + transport blips retry.
  """

  require Logger

  alias EllieAi.HttpClient

  @default_base_url "https://api.telnyx.com"

  @doc "telnyx requires this before audio flows."
  @spec answer(String.t(), keyword()) :: :ok | {:error, term()}
  def answer(call_control_id, opts \\ []) do
    post_action(call_control_id, "answer", %{}, opts)
  end

  @doc """
  μ-law 8kHz so the bytes pass straight through to openai realtime's
  `g711_ulaw` format with no transcoding.
  """
  @spec streaming_start(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def streaming_start(call_control_id, stream_url, opts \\ []) do
    body = %{
      stream_url: stream_url,
      stream_track: "both_tracks",
      stream_bidirectional_codec: "PCMU",
      stream_bidirectional_mode: "rtp"
    }

    post_action(call_control_id, "streaming_start", body, opts)
  end

  @spec hangup(String.t(), keyword()) :: :ok | {:error, term()}
  def hangup(call_control_id, opts \\ []) do
    post_action(call_control_id, "hangup", %{}, opts)
  end

  @spec dial(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def dial(connection_id, to, from, webhook_url, opts \\ []) do
    body = %{
      connection_id: connection_id,
      to: to,
      from: from,
      webhook_url: webhook_url
    }

    url = "#{base_url()}/v2/calls"

    Req.post(
      url,
      HttpClient.request_options(__MODULE__,
        json: body,
        auth: {:bearer, api_key()},
        retry: :transient,
        max_retries: Keyword.get(opts, :max_retries, 2)
      )
    )
    |> case do
      {:ok, %Req.Response{status: status, body: %{"data" => %{"call_control_id" => new_ccid}}}}
      when status in 200..299 ->
        {:ok, new_ccid}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("telnyx dial returned #{status}: #{inspect(body)}")
        {:error, {:http, status, body}}

      {:error, reason} ->
        Logger.warning("telnyx dial transport failed: #{inspect(reason)}")
        {:error, {:transport, reason}}
    end
  end

  @doc """
  once bridged, audio flows directly between the two legs and our media
  stream is muted.
  """
  @spec bridge(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def bridge(call_control_id, other_call_control_id, opts \\ []) do
    post_action(
      call_control_id,
      "bridge",
      %{call_control_id: other_call_control_id},
      opts
    )
  end

  @spec speak(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def speak(call_control_id, text, opts \\ []) when is_binary(call_control_id) and is_binary(text) do
    body = %{
      payload: text,
      voice: Keyword.get(opts, :voice, "Polly.Joanna"),
      language: Keyword.get(opts, :language, "en-US")
    }

    post_action(call_control_id, "speak", body, opts)
  end

  defp post_action(call_control_id, action, body, opts) do
    url = "#{base_url()}/v2/calls/#{call_control_id}/actions/#{action}"

    Req.post(
      url,
      HttpClient.request_options(__MODULE__,
        json: body,
        auth: {:bearer, api_key()},
        retry: :transient,
        max_retries: Keyword.get(opts, :max_retries, 3)
      )
    )
    |> handle_response(action)
  end

  defp handle_response({:ok, %Req.Response{status: status}}, _action) when status in 200..299,
    do: :ok

  defp handle_response({:ok, %Req.Response{status: status, body: body}}, action) do
    Logger.warning("telnyx #{action} returned #{status}: #{inspect(body)}")
    {:error, {:http, status, body}}
  end

  defp handle_response({:error, reason}, action) do
    Logger.warning("telnyx #{action} transport failed: #{inspect(reason)}")
    {:error, {:transport, reason}}
  end

  defp base_url do
    Application.get_env(:ellie_ai, __MODULE__, [])
    |> Keyword.get(:base_url, @default_base_url)
  end

  defp api_key do
    Application.get_env(:ellie_ai, __MODULE__, [])
    |> Keyword.get(:api_key) ||
      System.get_env("TELNYX_API_KEY") ||
      "test-telnyx-api-key"
  end
end
