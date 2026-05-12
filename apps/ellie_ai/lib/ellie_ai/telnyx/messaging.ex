defmodule EllieAi.Telnyx.Messaging do
  @moduledoc """
  outbound sms via the telnyx messaging api. inbound sms arrives via the
  message webhook controller, not here.
  """

  alias EllieAi.Orgs.Org

  require Logger

  @default_base_url "https://api.telnyx.com"

  @doc """
  returns the telnyx message id so the caller can stamp it onto a
  transcript turn for dedup against the eventual webhook receipt.
  """
  @spec send_sms(Org.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def send_sms(%Org{telnyx_phone_number: from}, _to, _text) when from in [nil, ""] do
    {:error, :no_telnyx_phone_number}
  end

  def send_sms(%Org{telnyx_phone_number: from}, to_phone, text)
      when is_binary(to_phone) and is_binary(text) do
    url = "#{base_url()}/v2/messages"
    body = %{from: from, to: to_phone, text: text}
    started = System.monotonic_time(:millisecond)

    case Req.post(url,
           json: body,
           auth: {:bearer, api_key()},
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %Req.Response{status: status, body: %{"data" => %{"id" => id}}}}
      when status in 200..299 ->
        dur = System.monotonic_time(:millisecond) - started
        Logger.info("telnyx send_sms ok id=#{id} to=#{to_phone} in #{dur}ms")
        {:ok, id}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("telnyx send_sms returned #{status}: #{inspect(body)}")
        {:error, {:http, status, body}}

      {:error, reason} ->
        Logger.warning("telnyx send_sms transport failed: #{inspect(reason)}")
        {:error, {:transport, reason}}
    end
  end

  defp base_url do
    Application.get_env(:ellie_ai, EllieAi.Telnyx.Client, [])
    |> Keyword.get(:base_url, @default_base_url)
  end

  defp api_key do
    Application.get_env(:ellie_ai, EllieAi.Telnyx.Client, [])
    |> Keyword.get(:api_key) ||
      System.get_env("TELNYX_API_KEY") ||
      "test-telnyx-api-key"
  end
end
