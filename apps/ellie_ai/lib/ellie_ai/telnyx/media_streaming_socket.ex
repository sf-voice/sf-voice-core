defmodule EllieAi.Telnyx.MediaStreamingSocket do
  @moduledoc """
  websock handler for telnyx media streaming. inbound + outbound are both
  raw μ-law bytes, base64-encoded inside the json frame — telnyx ignores
  `stream_bidirectional_mode: "rtp"` for these and frames everything as
  raw codec bytes.
  """

  @behaviour WebSock

  alias EllieAi.Calls
  alias EllieAi.Calls.{CallServer, CallRegistry}
  alias EllieAi.Telnyx.Rtp

  require Logger

  # AUDIO_CAPTURE_OUT=true mr dev → writes the first 5s of inbound
  # μ-law to priv/dev/captured_audio.ulaw for offline inspection.
  @audio_capture_budget_bytes 40_000

  @impl true
  def init(_opts) do
    {:ok,
     %{
       ccid: nil,
       first_media_logged: false,
       outbound_rtp: Rtp.new_outbound_state(),
       inbound_drops: %{},
       audio_capture: init_audio_capture()
     }}
  end

  defp init_audio_capture do
    case System.get_env("AUDIO_CAPTURE_OUT") do
      v when v in ["true", "1"] -> %{bytes_left: @audio_capture_budget_bytes, accumulated: []}
      _ -> nil
    end
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
    state = maybe_capture_audio(state, mulaw_bytes)

    frame =
      Jason.encode!(%{
        event: "media",
        media: %{payload: Base.encode64(mulaw_bytes)}
      })

    {:push, {:text, frame}, state}
  end

  def handle_info(msg, state) do
    Logger.debug("media_streaming_socket unhandled info: #{inspect(msg)}")
    {:ok, state}
  end

  defp maybe_capture_audio(%{audio_capture: nil} = state, _bytes), do: state

  defp maybe_capture_audio(%{audio_capture: cap} = state, bytes) do
    take = min(cap.bytes_left, byte_size(bytes))
    slice = binary_part(bytes, 0, take)
    cap = %{bytes_left: cap.bytes_left - take, accumulated: [cap.accumulated, slice]}

    if cap.bytes_left == 0 do
      flush_audio_capture(cap.accumulated)
      %{state | audio_capture: nil}
    else
      %{state | audio_capture: cap}
    end
  end

  defp flush_audio_capture(iolist) do
    path = Path.join(:code.priv_dir(:ellie_ai), "dev/captured_audio.ulaw")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, iolist)

    Logger.info(
      "audio capture: wrote #{@audio_capture_budget_bytes} bytes (5s μ-law @ 8kHz) to #{path}. " <>
        "play with: ffplay -f mulaw -ar 8000 -ac 1 #{path}"
    )
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "media_streaming_socket terminate: #{inspect(reason)} ccid=#{state.ccid}" <>
        inbound_drop_summary(state.inbound_drops)
    )

    # short call may end before the 5s capture budget fills — flush what
    # we have so the partial dump isn't lost.
    case state.audio_capture do
      %{accumulated: acc, bytes_left: left} when left < @audio_capture_budget_bytes ->
        flush_audio_capture(acc)

      _ ->
        :ok
    end

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

    Logger.info("telnyx media streaming start ccid=#{ccid} codec=#{encoding} rate=#{sample_rate}")

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

  defp handle_inbound_media(b64, state) do
    case decode_b64(b64) do
      {:ok, mulaw} ->
        state =
          if not state.first_media_logged do
            Logger.info("telnyx first media frame: ccid=#{state.ccid} bytes=#{byte_size(mulaw)}")

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
