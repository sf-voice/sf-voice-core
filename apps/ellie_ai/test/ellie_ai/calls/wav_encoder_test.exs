defmodule EllieAi.Calls.WavEncoderTest do
  use ExUnit.Case, async: true

  alias EllieAi.Calls.WavEncoder

  describe "encode_stereo/2" do
    test "produces a riff/wave header with the right format fields" do
      inbound = <<0xFF, 0x7F, 0x00>>
      outbound = <<0xFF, 0x00, 0x7F>>

      {iodata, duration_ms} = WavEncoder.encode_stereo(inbound, outbound)
      bin = IO.iodata_to_binary(iodata)

      assert <<"RIFF", _chunk::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16,
               2::little-16, 8000::little-32, _byte_rate::little-32, _block::little-16,
               16::little-16, "data", data_size::little-32, _rest::binary>> = bin

      assert data_size == 3 * 2 * 2
      assert duration_ms == div(3 * 1000, 8000)
    end

    test "pads the shorter stream with silence" do
      inbound = <<0xFF, 0xFF, 0xFF, 0xFF>>
      outbound = <<0xFF>>

      {iodata, _ms} = WavEncoder.encode_stereo(inbound, outbound)
      bin = IO.iodata_to_binary(iodata)

      <<_header::binary-size(44), samples::binary>> = bin
      assert byte_size(samples) == 4 * 2 * 2
    end

    test "empty inputs produce a valid zero-length wav" do
      {iodata, duration_ms} = WavEncoder.encode_stereo(<<>>, <<>>)
      bin = IO.iodata_to_binary(iodata)

      assert <<"RIFF", _chunk::little-32, "WAVE", _rest::binary>> = bin
      assert duration_ms == 0
    end

    test "sample rate getter exposes the expected 8 khz" do
      assert WavEncoder.sample_rate() == 8000
    end
  end
end
