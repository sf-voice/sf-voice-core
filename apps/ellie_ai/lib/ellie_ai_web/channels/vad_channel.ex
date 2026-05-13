defmodule EllieAiWeb.VadChannel do
  @moduledoc """
  one channel pid per audio stream. holds per-stream silero recurrent
  state + EOT hysteresis. one bad client can't poison anyone else's
  inference.

  topic shape: `vad:stream:<caller_chosen_id>` — the channel doesn't
  care about the id; phoenix uses it as a routing handle.

  ## join params

      %{
        "sample_rate" => 8000  # optional; 8000 or 16000. default 8000.
        "silence_ms"  => 700   # optional; ms of sub-threshold audio
                               # before :speech_end fires. default 700.
      }

  on join, the server replies with the exact format it expects so the
  client doesn't have to hardcode anything:

      %{
        sample_rate:        8000,
        samples_per_window: 256,
        bytes_per_window:   1024,
        window_ms:          32,
        sample_dtype:       "float32_le",
        speech_threshold:   0.5,
        silence_threshold:  0.35
      }

  ## wire protocol

  the client pushes one window per binary message:

      push("audio", <<f32_samples::binary>>)   # bytes_per_window bytes

  the server pushes one reply per window:

      push("frame", %{prob: 0.42})             # speech probability
      push("frame", %{prob: 0.91, event: "speech_start"})
      push("frame", %{prob: 0.05, event: "speech_end"})

  the `event` key is present only on transition frames. consumers that
  only care about EOT subscribe to `event == "speech_end"`.

  ## why two sample rates

  silero supports 8khz and 16khz natively with different window sizes.
  ellie's own call path is 8khz (telnyx delivers G.711 μ-law). web /
  browser-mic consumers usually have 16khz after their own resampling.
  rather than force a rate on the client, the channel negotiates at
  join and validates every subsequent frame.

  wrong-size frames return `{:error, :bad_window_size}` with the
  expected byte count so the client fails loudly instead of silently
  producing garbage probabilities.
  """

  use Phoenix.Channel

  alias EllieAi.Calls.SileroVad
  alias EllieAi.Vad.Hysteresis

  require Logger

  # window is 32ms regardless of sample rate — at 8khz that's 256
  # samples, at 16khz that's 512. SileroVad.window_size_for/1 maps it.
  @window_ms 32

  @supported_sample_rates [8000, 16000]

  @impl true
  def join("vad:stream:" <> _id, params, socket) do
    with {:ok, sample_rate} <- parse_sample_rate(params),
         silence_ms = parse_silence_ms(params),
         window_size = SileroVad.window_size_for(sample_rate),
         window_bytes = window_size * 4 do
      socket =
        socket
        |> assign(:rnn_state, SileroVad.initial_state())
        |> assign(:hysteresis, Hysteresis.new(silence_ms: silence_ms, window_ms: @window_ms))
        |> assign(:sample_rate, sample_rate)
        |> assign(:window_size, window_size)
        |> assign(:window_bytes, window_bytes)

      Logger.info(
        "vad_channel join: topic=#{socket.topic} sample_rate=#{sample_rate} " <>
          "window=#{window_size}samples/#{window_bytes}B silence_ms=#{silence_ms}"
      )

      thresholds = Hysteresis.thresholds()

      reply = %{
        sample_rate: sample_rate,
        samples_per_window: window_size,
        bytes_per_window: window_bytes,
        window_ms: @window_ms,
        sample_dtype: "float32_le",
        speech_threshold: thresholds.speech,
        silence_threshold: thresholds.silence
      }

      {:ok, reply, socket}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "unknown topic"}}

  @impl true
  def handle_in("audio", {:binary, audio}, socket) do
    expected = socket.assigns.window_bytes

    if byte_size(audio) == expected do
      run_inference(audio, socket)
    else
      {:reply,
       {:error,
        %{
          reason: "bad_window_size",
          sample_rate: socket.assigns.sample_rate,
          expected_bytes: expected,
          got_bytes: byte_size(audio)
        }}, socket}
    end
  end

  # any non-binary "audio" message is a protocol error on the caller's
  # side — we don't try to coerce json arrays into f32. send binary or
  # don't bother.
  def handle_in("audio", _payload, socket) do
    {:reply, {:error, %{reason: "audio must be a binary push"}}, socket}
  end

  # ── helpers ───────────────────────────────────────────────────────────

  defp run_inference(audio, socket) do
    samples =
      for <<sample::little-float-32 <- audio>>, do: sample

    {prob, new_rnn} =
      SileroVad.infer(samples, socket.assigns.rnn_state, socket.assigns.sample_rate)

    {new_hyst, events} = Hysteresis.feed(socket.assigns.hysteresis, prob)

    push(socket, "frame", payload_for(prob, events))

    {:noreply,
     socket
     |> assign(:rnn_state, new_rnn)
     |> assign(:hysteresis, new_hyst)}
  end

  defp payload_for(prob, []), do: %{prob: prob}

  defp payload_for(prob, [event | _]) do
    # at most one transition event per window; silero hysteresis never
    # produces more, so emitting the first is the same as emitting all.
    %{prob: prob, event: Atom.to_string(event)}
  end

  defp parse_sample_rate(%{"sample_rate" => sr}) when sr in @supported_sample_rates do
    {:ok, sr}
  end

  defp parse_sample_rate(%{"sample_rate" => other}) do
    {:error,
     %{
       reason: "unsupported_sample_rate",
       got: other,
       supported: @supported_sample_rates
     }}
  end

  defp parse_sample_rate(_), do: {:ok, 8000}

  defp parse_silence_ms(%{"silence_ms" => ms}) when is_integer(ms) and ms > 0, do: ms
  defp parse_silence_ms(_), do: 700
end
