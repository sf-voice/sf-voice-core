defmodule EllieAi.Telnyx.Signature do
  @moduledoc """
  ed25519 signature verification for inbound telnyx webhooks. signed
  message is `<timestamp>|<raw_body>`; ed25519 hashes internally with
  sha-512 so we don't pre-hash. public key is base64-encoded 32 bytes
  from `TELNYX_PUBLIC_KEY`.
  """

  # defends against replay without being so tight that clock skew trips us up.
  @max_skew_seconds 5 * 60

  @typedoc "result of verify/4."
  @type result :: :ok | {:error, :bad_signature | :stale_timestamp | :malformed}

  @doc """
  callers should map errors to 401/400 — never reveal which check failed
  to the client. `body` must be the exact bytes telnyx sent, before any
  json parsing.
  """
  @spec verify(String.t(), String.t(), binary(), String.t()) :: result()
  def verify(signature_b64, timestamp, body, public_key_b64)
      when is_binary(signature_b64) and is_binary(timestamp) and is_binary(body) and
             is_binary(public_key_b64) do
    with :ok <- check_timestamp(timestamp),
         {:ok, signature} <- decode_b64(signature_b64),
         {:ok, public_key} <- decode_b64(public_key_b64),
         message <- "#{timestamp}|#{body}",
         true <- :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519]) do
      :ok
    else
      false -> {:error, :bad_signature}
      {:error, _} = err -> err
    end
  rescue
    # wrong-length sig, malformed key, etc. — flatten to :bad_signature so we don't leak crypto internals.
    _ -> {:error, :bad_signature}
  end

  def verify(_, _, _, _), do: {:error, :malformed}

  defp check_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {ts, ""} when ts > 0 ->
        now = System.system_time(:second)
        if abs(now - ts) <= @max_skew_seconds, do: :ok, else: {:error, :stale_timestamp}

      _ ->
        {:error, :malformed}
    end
  end

  defp decode_b64(b64) do
    case Base.decode64(b64) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :malformed}
    end
  end
end
