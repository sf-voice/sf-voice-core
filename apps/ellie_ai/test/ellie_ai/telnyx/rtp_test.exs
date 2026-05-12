defmodule EllieAi.Telnyx.RtpTest do
  use ExUnit.Case, async: true

  alias EllieAi.Telnyx.Rtp

  describe "encode/2" do
    test "produces a 12-byte fixed header + payload" do
      payload = String.duplicate(<<0xFF>>, 160)
      state = %{seq: 0, ts: 0, ssrc: 0xDEADBEEF}

      {packet, _} = Rtp.encode(payload, state)
      assert byte_size(packet) == 12 + 160
    end

    test "advances seq by 1 with 16-bit wrap" do
      state = %{seq: 0xFFFF, ts: 0, ssrc: 1}
      {_, next} = Rtp.encode(<<0xFF>>, state)
      assert next.seq == 0
    end

    test "advances ts by payload byte count with 32-bit wrap" do
      state = %{seq: 0, ts: 0xFFFFFFFF, ssrc: 1}
      {_, next} = Rtp.encode(<<0xFF, 0xFF, 0xFF>>, state)
      # 0xFFFFFFFF + 3 = 0xFFFFFFFE after wrap (rem _, 2^32)
      assert next.ts == 2
    end

    test "ssrc is fixed across packets" do
      state = %{seq: 0, ts: 0, ssrc: 0xCAFEBABE}
      {_, s1} = Rtp.encode(<<0xFF>>, state)
      {_, s2} = Rtp.encode(<<0xFF>>, s1)
      assert s1.ssrc == 0xCAFEBABE
      assert s2.ssrc == 0xCAFEBABE
    end
  end

  describe "decode/1" do
    test "round-trip: encode → decode returns same payload + seq + ts" do
      payload = String.duplicate(<<0xAA>>, 160)
      state = %{seq: 1234, ts: 567_890, ssrc: 0xDEADBEEF}

      {packet, _} = Rtp.encode(payload, state)
      assert {:ok, decoded} = Rtp.decode(packet)
      assert decoded.payload == payload
      assert decoded.seq == 1234
      assert decoded.ts == 567_890
      assert decoded.pt == 0
    end

    test "rejects packets with wrong RTP version" do
      bad = <<1::2, 0::1, 0::1, 0::4, 0::1, 0::7, 0::16, 0::32, 0::32>>
      assert {:error, {:bad_version, 1}} = Rtp.decode(bad)
    end

    test "rejects non-PCMU payload types" do
      # PT=8 = PCMA, not PCMU
      bad = <<2::2, 0::1, 0::1, 0::4, 0::1, 8::7, 0::16, 0::32, 0::32, 0xFF>>
      assert {:error, {:unexpected_payload_type, 8}} = Rtp.decode(bad)
    end

    test "rejects truncated packets" do
      assert {:error, :too_short} = Rtp.decode(<<0xFF, 0xFF>>)
    end

    test "skips CSRC list correctly" do
      # CC=2, 8 bytes of CSRC, then 4 bytes of payload
      csrcs = <<1::32, 2::32>>
      payload = <<0x10, 0x20, 0x30, 0x40>>
      packet = <<2::2, 0::1, 0::1, 2::4, 0::1, 0::7, 0::16, 0::32, 0::32>> <> csrcs <> payload

      assert {:ok, %{payload: ^payload}} = Rtp.decode(packet)
    end
  end

  describe "new_outbound_state/0" do
    test "produces valid initial state values" do
      state = Rtp.new_outbound_state()
      assert state.seq in 0..0xFFFF
      assert state.ts in 0..0xFFFFFFFF
      assert state.ssrc in 0..0xFFFFFFFF
    end
  end
end
