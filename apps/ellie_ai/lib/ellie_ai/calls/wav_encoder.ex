defmodule EllieAi.Calls.WavEncoder do
  @moduledoc """
  encode inbound (left) + outbound (right) μ-law streams into a stereo
  8khz pcm16 wav. shorter stream zero-padded.
  """

  alias EllieAi.Calls.Ulaw

  @sample_rate 8000
  @bits_per_sample 16
  @num_channels 2
  @byte_rate @sample_rate * @num_channels * div(@bits_per_sample, 8)
  @block_align @num_channels * div(@bits_per_sample, 8)

  @doc """
  encode inbound + outbound μ-law into a stereo wav file (iodata).

  inbound goes to the left channel, outbound to the right. shorter stream
  is padded with silence so the file ends at max(inbound, outbound) length.
  """
  @spec encode_stereo(binary(), binary()) :: {iodata(), pos_integer()}
  def encode_stereo(inbound_ulaw, outbound_ulaw)
      when is_binary(inbound_ulaw) and is_binary(outbound_ulaw) do
    total_samples = max(byte_size(inbound_ulaw), byte_size(outbound_ulaw))
    data_size = total_samples * @block_align
    duration_ms = div(total_samples * 1000, @sample_rate)

    header = riff_header(data_size)
    interleaved = interleave(inbound_ulaw, outbound_ulaw, total_samples)

    {[header, interleaved], duration_ms}
  end

  # walk both binaries in lockstep, decoding each byte to int16 and
  # emitting <left, right> pairs. when one runs out, substitute 0.
  defp interleave(left, right, n) do
    do_interleave(left, right, n, [])
  end

  defp do_interleave(_l, _r, 0, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp do_interleave(left, right, n, acc) do
    {l_sample, left_rest} = pop_sample(left)
    {r_sample, right_rest} = pop_sample(right)
    pair = <<l_sample::little-signed-16, r_sample::little-signed-16>>
    do_interleave(left_rest, right_rest, n - 1, [pair | acc])
  end

  defp pop_sample(<<b, rest::binary>>), do: {Ulaw.decode_byte(b), rest}
  defp pop_sample(<<>>), do: {0, <<>>}

  # riff/wav header. all little-endian. data_size is the byte length of the
  # interleaved sample payload (not counting the header itself).
  defp riff_header(data_size) do
    chunk_size = 36 + data_size

    <<
      "RIFF",
      chunk_size::little-32,
      "WAVE",
      "fmt ",
      16::little-32,
      1::little-16,
      @num_channels::little-16,
      @sample_rate::little-32,
      @byte_rate::little-32,
      @block_align::little-16,
      @bits_per_sample::little-16,
      "data",
      data_size::little-32
    >>
  end

  @doc "sample rate the encoder writes (for tests and callers)."
  def sample_rate, do: @sample_rate
end
