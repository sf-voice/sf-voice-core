defmodule EllieAi.Telnyx.Rtp do
  @moduledoc """
  minimal rtp framing for telnyx media streaming bidirectional audio.

  reference: rfc 3550 §5.1 (rtp fixed header).
  https://datatracker.ietf.org/doc/html/rfc3550

      0                   1                   2                   3
      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     |V=2|P|X|  CC   |M|     PT      |       sequence number         |
     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     |                           timestamp                           |
     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     |           synchronization source (SSRC) identifier            |
     +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
     |            contributing source (CSRC) identifiers             |
     |                             ....                              |
     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

  used because telnyx's `streaming_start` is configured with
  `stream_bidirectional_mode: "rtp"` (per ellie_ai/lib/ellie_ai/telnyx/client.ex).
  inbound media frames arrive as base64-encoded rtp packets; outbound
  frames must be base64-encoded rtp packets too.

  payload type for PCMU is 0 (rfc 3551). 8khz, 1 channel.
  https://datatracker.ietf.org/doc/html/rfc3551

  jitter / packet reordering / loss recovery: NONE in v0. we hand the
  μ-law payload straight to openai's input_audio_buffer.append in
  receive order. openai's vad + our silero vad both tolerate small
  reorders within a single utterance better than dropouts.
  """

  require Logger

  @rtp_version 2
  @pcmu_payload_type 0
  # 20ms of 8khz μ-law = 160 samples = 160 timestamp ticks per packet.
  @samples_per_packet 160

  @typedoc "decoded inbound packet metadata."
  @type packet :: %{
          payload: binary(),
          seq: non_neg_integer(),
          ts: non_neg_integer(),
          pt: 0..127
        }

  @typedoc "outbound stream state. carry across packets to advance seq + ts."
  @type out_state :: %{seq: non_neg_integer(), ts: non_neg_integer(), ssrc: non_neg_integer()}

  # ── decode inbound ──────────────────────────────────────────────────────

  @doc """
  decode an rtp packet. returns `{:ok, %{payload, seq, ts, pt}}` or
  `{:error, reason}`.

  drops packets with version != 2, payload type != PCMU (we only handle
  audio), and any malformed extension headers. caller should log + drop
  silently — telnyx should never send these.
  """
  @spec decode(binary()) :: {:ok, packet()} | {:error, atom()}
  def decode(<<
        # first byte: 2 bits version, 1 bit padding, 1 bit extension, 4 bits CSRC count
        version::2,
        padding::1,
        extension::1,
        cc::4,
        # second byte: 1 bit marker, 7 bits payload type
        _marker::1,
        pt::7,
        seq::16-big,
        ts::32-big,
        _ssrc::32-big,
        rest::binary
      >>) do
    cond do
      version != @rtp_version ->
        {:error, {:bad_version, version}}

      pt != @pcmu_payload_type ->
        {:error, {:unexpected_payload_type, pt}}

      true ->
        with {:ok, after_csrc} <- skip_csrc(rest, cc),
             {:ok, payload_with_padding} <- skip_extension(after_csrc, extension),
             {:ok, payload} <- strip_padding(payload_with_padding, padding) do
          {:ok, %{payload: payload, seq: seq, ts: ts, pt: pt}}
        end
    end
  end

  def decode(_), do: {:error, :too_short}

  defp skip_csrc(bin, 0), do: {:ok, bin}

  defp skip_csrc(bin, cc) do
    bytes = cc * 4

    case bin do
      <<_::binary-size(bytes), rest::binary>> -> {:ok, rest}
      _ -> {:error, :truncated_csrc}
    end
  end

  # extension header: 16-bit defined-by-profile, 16-bit length-in-32-bit-words,
  # then `length` 32-bit words. we don't read the data, just skip past it.
  defp skip_extension(bin, 0), do: {:ok, bin}

  defp skip_extension(<<_id::16, len::16-big, rest::binary>>, 1) do
    bytes = len * 4

    case rest do
      <<_::binary-size(bytes), payload::binary>> -> {:ok, payload}
      _ -> {:error, :truncated_extension}
    end
  end

  defp skip_extension(_, _), do: {:error, :bad_extension_header}

  # padding bit: last byte of payload says how many trailing bytes (incl
  # itself) to ignore. rare in practice for audio.
  defp strip_padding(bin, 0), do: {:ok, bin}

  defp strip_padding(bin, 1) when byte_size(bin) > 0 do
    pad_len = :binary.last(bin)

    if pad_len > 0 and pad_len <= byte_size(bin) do
      {:ok, binary_part(bin, 0, byte_size(bin) - pad_len)}
    else
      {:error, :bad_padding}
    end
  end

  defp strip_padding(_, _), do: {:error, :bad_padding}

  # ── encode outbound ─────────────────────────────────────────────────────

  @doc """
  initial outbound state. ssrc is randomized per call so concurrent calls
  don't collide on telnyx's side.
  """
  @spec new_outbound_state() :: out_state()
  def new_outbound_state do
    %{
      seq: :rand.uniform(0x10000) - 1,
      ts: :rand.uniform(0x100000000) - 1,
      ssrc: :rand.uniform(0x100000000) - 1
    }
  end

  @doc """
  encode a μ-law payload as an rtp packet. returns `{packet_bytes,
  next_state}` so the caller threads state forward.

  always advances by `byte_size(payload)` ticks (μ-law is 1 byte / sample
  / 1 tick at 8khz). seq increments by 1 with 16-bit wrap. ts wraps at
  32 bits.
  """
  @spec encode(binary(), out_state()) :: {binary(), out_state()}
  def encode(payload, %{seq: seq, ts: ts, ssrc: ssrc} = state) when is_binary(payload) do
    header =
      <<@rtp_version::2, 0::1, 0::1, 0::4, 0::1, @pcmu_payload_type::7, seq::16-big, ts::32-big,
        ssrc::32-big>>

    packet = header <> payload

    next_state = %{
      state
      | seq: rem(seq + 1, 0x10000),
        ts: rem(ts + byte_size(payload), 0x100000000)
    }

    {packet, next_state}
  end

  @doc "default samples-per-packet for μ-law @ 8kHz / 20ms framing."
  def samples_per_packet, do: @samples_per_packet
end
