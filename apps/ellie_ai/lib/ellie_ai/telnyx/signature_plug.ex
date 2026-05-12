defmodule EllieAi.Telnyx.SignaturePlug do
  @moduledoc """
  gates `/telnyx/*` on a valid ed25519 signature. 401 + halt on failure,
  with a structured diagnostic log (headers + body fingerprint, never the
  body) so we can triage without leaking PII. expects the raw body cached
  in `conn.assigns.raw_body` by `CacheBodyReader`. public key from app
  config; dev/test fall back to the committed test pubkey in priv/dev.
  """

  @behaviour Plug

  import Plug.Conn

  alias EllieAi.Telnyx.Signature

  require Logger

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case verify(conn) do
      :ok ->
        conn

      {:error, reason} ->
        log_diagnostic(conn, reason)
        conn |> send_resp(401, "") |> halt()
    end
  end

  defp verify(conn) do
    case public_key() do
      nil ->
        # missing key is always a hard failure — no env-conditional bypass.
        # dev must explicitly set the test key (see priv/dev/README.md).
        {:error, :public_key_missing}

      public_key_b64 ->
        with [signature_b64] <- get_req_header(conn, "telnyx-signature-ed25519"),
             [timestamp] <- get_req_header(conn, "telnyx-timestamp"),
             body when is_binary(body) <- raw_body(conn) do
          Signature.verify(signature_b64, timestamp, body, public_key_b64)
        else
          _ -> {:error, :missing_headers}
        end
    end
  end

  defp public_key do
    Application.get_env(:ellie_ai, :telnyx_public_key) ||
      System.get_env("TELNYX_PUBLIC_KEY") ||
      dev_test_public_key()
  end

  # dev/test fall back so the in-VM signing helper can produce verifiable
  # webhooks without a Mission Control round-trip. nil in :prod.
  defp dev_test_public_key do
    if env() in [:dev, :test] do
      path = Path.join(:code.priv_dir(:ellie_ai), "dev/telnyx_test_pubkey.b64")

      case File.read(path) do
        {:ok, b64} -> String.trim(b64)
        {:error, _} -> nil
      end
    end
  end

  defp env do
    cond do
      Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) -> Mix.env()
      System.get_env("RELEASE_NAME") -> :prod
      true -> :prod
    end
  end

  defp raw_body(conn) do
    case conn.assigns[:raw_body] do
      [_ | _] = chunks -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
      _ -> nil
    end
  end

  # fingerprint the body (sha256, first 16 chars) so we can correlate
  # failing webhooks across log lines without dumping raw body (PII).
  defp log_diagnostic(conn, reason) do
    headers = %{
      sig: header_present?(conn, "telnyx-signature-ed25519"),
      ts: header_present?(conn, "telnyx-timestamp")
    }

    body_info =
      case raw_body(conn) do
        nil -> %{present: false}
        b -> %{present: true, length: byte_size(b), sha256_prefix: body_fingerprint(b)}
      end

    Logger.warning(
      "telnyx signature failed: reason=#{inspect(reason)} headers=#{inspect(headers)} body=#{inspect(body_info)}"
    )
  end

  defp header_present?(conn, name) do
    case get_req_header(conn, name) do
      [v | _] -> "yes(len=#{String.length(v)})"
      _ -> "no"
    end
  end

  defp body_fingerprint(body) do
    body
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end
end
