defmodule EllieAi.Telnyx.MediaStreamingSocket do
  @moduledoc """

  - **inbound** is raw μ-law: telnyx delivers
  codec bytes directly, no RTP header.
  - **outbound** is RTP-wrapped:
  `stream_bidirectional_mode: "rtp"` only governs what we send back.
  """

  @behaviour WebSock

  alias EllieAi.Calls
  alias EllieAi.Calls.{CallServer, CallRegistry}
  alias EllieAi.Telnyx.Rtp

  require Logger

  @impl true
  def init(_opts) do
    {:ok,
     %{
       ccid: nil,
       first_media_logged: false,
       outbound_rtp: Rtp.new_outbound_state(),

       inbound_drops: %{}
     }}
  end

  @impl true
  def handle_in({payload, [opcode: :text]}, state) do
    case Jason.decode(payload) do
      {:ok, event} -> handle_event(event, state)
      {:error, _} -> {:ok, state}
    end
  end

  def handle_in(_other, state), do: {:ok, state}

  @impl true
  def handle_info({:outbound_audio, mulaw_bytes}, state) when is_binary(mulaw_bytes) do
    {rtp_packet, next_rtp} = Rtp.encode(mulaw_bytes, state.outbound_rtp)

    frame =
      Jason.encode!(%{
        event: "media",
        media: %{payload: Base.encode64(rtp_packet)}
      })

    {:push, {:text, frame}, %{state | outbound_rtp: next_rtp}}
  end

  def handle_info(msg, state) do
    Logger.debug("media_streaming_socket unhandled info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "media_streaming_socket terminate: #{inspect(reason)} ccid=#{state.ccid}" <>
        inbound_drop_summary(state.inbound_drops)
    )

    if state.ccid do
      Calls.on_hangup(state.ccid)
    end

    :ok
  end

  defp inbound_drop_summary(drops) when map_size(drops) == 0, do: ""

  defp inbound_drop_summary(drops) do
    " inbound_drops=" <>
      (drops
       |> Enum.map(fn {reason, count} -> "#{inspect(reason)}×#{count}" end)
       |> Enum.join(","))
  end

  defp handle_event(%{"event" => "connected"}, state) do
    Logger.debug("telnyx media streaming: connected")
    {:ok, state}
  end

  defp handle_event(%{"event" => "start", "start" => start}, state) do
    ccid = start["call_control_id"]
    encoding = get_in(start, ["media_format", "encoding"])
    sample_rate = get_in(start, ["media_format", "sample_rate"])

    Logger.info(
      "telnyx media streaming start ccid=#{ccid} codec=#{encoding} rate=#{sample_rate}"
    )

    case Registry.register(CallRegistry.name(), {:media_socket, ccid}, nil) do
      {:ok, _} ->
        CallServer.register_media_socket(ccid, self())
        Calls.on_media_started(ccid, start)
        {:ok, %{state | ccid: ccid}}

      {:error, {:already_registered, _}} ->
        Logger.warning("media socket re-registration for ccid=#{ccid} — keeping existing")
        {:ok, %{state | ccid: ccid}}
    end
  end

  defp handle_event(%{"event" => "media", "media" => %{"payload" => b64} = media}, state)
       when is_binary(b64) do
    track = media["track"] || "inbound"

    if track == "inbound" do
      handle_inbound_media(b64, state)
    else
      # outbound track is telnyx echoing our own audio back. drop to avoid
      # a feedback loop into openai's input buffer.
      {:ok, state}
    end
  end

  defp handle_event(%{"event" => "stop"}, state) do
    Logger.info("telnyx media streaming stop ccid=#{state.ccid}")
    {:stop, :normal, state}
  end

  defp handle_event(%{"event" => "dtmf", "dtmf" => %{"digit" => digit}}, state) do
    Logger.info("dtmf #{digit} on ccid=#{state.ccid}")
    {:ok, state}
  end

  defp handle_event(%{"event" => "error"} = event, state) do
    Logger.error("telnyx media streaming error: #{inspect(event)}")
    {:ok, state}
  end

  defp handle_event(event, state) do
    Logger.debug(
      "telnyx media streaming event (unhandled): #{inspect(event, pretty: true, limit: :infinity, printable_limit: :infinity)}"
    )

    {:ok, state}
  end

  #   The payload contains a base64-encoded RTP payload (no headers).
  #    The RTP mode distinction applies to outbound messages you send,
  #    not how Telnyx frames inbound audio to us.
  #
  #   https://developers.telnyx.com/docs/voice/programmable-voice/media-streaming

  defp handle_inbound_media(b64, state) do
    case decode_b64(b64) do
      {:ok, mulaw} ->
        state =
          if not state.first_media_logged do
            Logger.info(
              "telnyx first media frame: ccid=#{state.ccid} bytes=#{byte_size(mulaw)}"
            )

            %{state | first_media_logged: true}
          else
            state
          end

        if state.ccid, do: Calls.on_inbound_audio(state.ccid, mulaw)
        {:ok, state}

      {:error, reason} ->
        {:ok, track_inbound_drop(state, reason)}
    end
  end

  defp track_inbound_drop(state, reason) do
    case Map.fetch(state.inbound_drops, reason) do
      :error ->
        Logger.warning(
          "inbound media drop (first occurrence — suppressing repeats): " <>
            "ccid=#{state.ccid} reason=#{inspect(reason)}"
        )

        %{state | inbound_drops: Map.put(state.inbound_drops, reason, 1)}

      {:ok, n} ->
        %{state | inbound_drops: Map.put(state.inbound_drops, reason, n + 1)}
    end
  end

  defp decode_b64(b64) do
    case Base.decode64(b64) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :bad_base64}
    end
  end

end
