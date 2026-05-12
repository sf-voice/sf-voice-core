defmodule EllieAi.Test.TelnyxSigningHelper do
  @moduledoc """
  signs synthetic telnyx webhook payloads with the dev test keypair so
  controller tests can post valid signatures into the SignaturePlug
  pipeline.

  the dev keypair lives in `priv/dev/` (committed; see priv/dev/README.md
  for why that's safe).
  """

  @doc """
  sign a json-encoded body. returns a list of `{header_name, value}`
  tuples ready to feed into `Plug.Conn.put_req_header/3`.

  message format mirrors `Signature.verify/4`: `"<ts>|<body>"`.
  """
  def headers_for(body) when is_binary(body) do
    timestamp = Integer.to_string(System.system_time(:second))
    privkey = load_priv_key()
    message = "#{timestamp}|#{body}"
    sig = :crypto.sign(:eddsa, :none, message, [privkey, :ed25519])

    [
      {"telnyx-signature-ed25519", Base.encode64(sig)},
      {"telnyx-timestamp", timestamp},
      {"content-type", "application/json"}
    ]
  end

  defp load_priv_key do
    :code.priv_dir(:ellie_ai)
    |> Path.join("dev/telnyx_test_privkey.b64")
    |> File.read!()
    |> String.trim()
    |> Base.decode64!()
  end
end
