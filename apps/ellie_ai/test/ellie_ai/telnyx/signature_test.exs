defmodule EllieAi.Telnyx.SignatureTest do
  use ExUnit.Case, async: true

  alias EllieAi.Telnyx.Signature

  setup do
    # generate a fresh ed25519 keypair for each test — no shared state,
    # no fixtures that rot when telnyx rotates anything on their side.
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    %{public_key_b64: Base.encode64(pub), private_key: priv}
  end

  describe "verify/4" do
    test "accepts a valid signature on a fresh timestamp", %{
      public_key_b64: pub_b64,
      private_key: priv
    } do
      timestamp = "#{System.system_time(:second)}"
      body = ~s({"event": "call.initiated", "call_control_id": "abc"})
      message = "#{timestamp}|#{body}"
      sig_b64 = sign(message, priv)

      assert :ok = Signature.verify(sig_b64, timestamp, body, pub_b64)
    end

    test "rejects a tampered body", %{public_key_b64: pub_b64, private_key: priv} do
      timestamp = "#{System.system_time(:second)}"
      body = ~s({"event": "call.initiated"})
      sig_b64 = sign("#{timestamp}|#{body}", priv)

      tampered = ~s({"event": "call.hangup"})
      assert {:error, :bad_signature} = Signature.verify(sig_b64, timestamp, tampered, pub_b64)
    end

    test "rejects a stale timestamp (older than 5 min)", %{
      public_key_b64: pub_b64,
      private_key: priv
    } do
      timestamp = "#{System.system_time(:second) - 6 * 60}"
      body = ~s({"event": "call.initiated"})
      sig_b64 = sign("#{timestamp}|#{body}", priv)

      assert {:error, :stale_timestamp} =
               Signature.verify(sig_b64, timestamp, body, pub_b64)
    end

    test "rejects a future timestamp beyond skew window", %{
      public_key_b64: pub_b64,
      private_key: priv
    } do
      timestamp = "#{System.system_time(:second) + 6 * 60}"
      body = ~s({"event": "call.initiated"})
      sig_b64 = sign("#{timestamp}|#{body}", priv)

      assert {:error, :stale_timestamp} =
               Signature.verify(sig_b64, timestamp, body, pub_b64)
    end

    test "rejects a malformed timestamp", %{public_key_b64: pub_b64} do
      assert {:error, :malformed} =
               Signature.verify("AAAA", "not-a-number", "body", pub_b64)
    end

    test "rejects garbage in the signature header without crashing", %{
      public_key_b64: pub_b64
    } do
      timestamp = "#{System.system_time(:second)}"
      assert {:error, _} = Signature.verify("not-base64!!!", timestamp, "body", pub_b64)
    end

    test "rejects when public key is the wrong length", %{private_key: priv} do
      timestamp = "#{System.system_time(:second)}"
      body = "{}"
      sig_b64 = sign("#{timestamp}|#{body}", priv)
      bad_pub = Base.encode64("too-short")

      assert {:error, :bad_signature} = Signature.verify(sig_b64, timestamp, body, bad_pub)
    end
  end

  defp sign(message, private_key) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode64()
  end
end
