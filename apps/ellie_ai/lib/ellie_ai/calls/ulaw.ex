defmodule EllieAi.Calls.Ulaw do
  @moduledoc """
  μ-law (g.711 pcmu) decoding via a compile-time 256-entry lookup table.
  """

  import Bitwise

  # pre-build the lookup at compile time. each entry is the int16 pcm
  # value for the corresponding μ-law byte index.
  decoded_table =
    for byte <- 0..255 do
      inverted = bxor(byte, 0xFF)
      sign = band(inverted, 0x80)
      exponent = band(bsr(inverted, 4), 0x07)
      mantissa = band(inverted, 0x0F)
      sample = bsl(bor(bsl(mantissa, 3), 0x84), exponent) - 0x84
      if sign != 0, do: -sample, else: sample
    end

  @table List.to_tuple(decoded_table)

  @inv_scale 1.0 / 32768.0

  @doc "decode one μ-law byte to its int16 pcm sample value."
  def decode_byte(b) when is_integer(b) and b in 0..255, do: elem(@table, b)

  @doc """
  decode a μ-law byte string into a list of float32 samples in [-1.0, 1.0).
  output length equals input byte size (one sample per byte).
  """
  def decode_to_floats(bytes) when is_binary(bytes) do
    for <<b <- bytes>>, do: elem(@table, b) * @inv_scale
  end
end
