defmodule EllieAi.Calls.UlawTest do
  use ExUnit.Case, async: true

  alias EllieAi.Calls.Ulaw

  describe "decode_byte/1" do
    test "0xff (μ-law silence) decodes to 0" do
      # in μ-law, 0xFF after inversion is 0x00 — sign 0, exp 0, mant 0,
      # which decodes to ((0<<3)+0x84)<<0 - 0x84 = 0.
      assert Ulaw.decode_byte(0xFF) == 0
    end

    test "0x00 (μ-law negative peak) decodes to a large negative value" do
      # byte 0x00 → invert → 0xFF: sign 1, exp 7, mant F → magnitude 32124, negative.
      sample = Ulaw.decode_byte(0x00)
      assert sample < -32_000
      assert sample > -33_000
    end

    test "0x80 (μ-law positive peak) decodes to a large positive value" do
      # byte 0x80 → invert → 0x7F: sign 0, exp 7, mant F → magnitude 32124, positive.
      sample = Ulaw.decode_byte(0x80)
      assert sample > 32_000
      assert sample < 33_000
    end

    test "0x7f (the second μ-law silence byte) decodes to 0" do
      # byte 0x7F → invert → 0x80: sign 1, exp 0, mant 0 → magnitude 0.
      assert Ulaw.decode_byte(0x7F) == 0
    end

    test "all 256 values decode without crashing and stay in int16 range" do
      for b <- 0..255 do
        s = Ulaw.decode_byte(b)
        assert is_integer(s)
        assert s >= -32_768 and s <= 32_767
      end
    end
  end

  describe "decode_to_floats/1" do
    test "empty binary returns empty list" do
      assert Ulaw.decode_to_floats(<<>>) == []
    end

    test "all-silence input stays at exactly 0.0" do
      bytes = String.duplicate(<<0xFF>>, 10)
      assert Ulaw.decode_to_floats(bytes) == List.duplicate(0.0, 10)
    end

    test "output length matches byte size, values in [-1.0, 1.0)" do
      bytes = for i <- 0..15, into: <<>>, do: <<i::8>>
      floats = Ulaw.decode_to_floats(bytes)

      assert length(floats) == 16
      Enum.each(floats, fn f ->
        assert is_float(f)
        assert f >= -1.0 and f < 1.0
      end)
    end
  end
end
