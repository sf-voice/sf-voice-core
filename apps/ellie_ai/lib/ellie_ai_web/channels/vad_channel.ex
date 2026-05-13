defmodule EllieAiWeb.VadChannel do
  @moduledoc """
  one channel pid per audio stream. holds per-stream silero recurrent
  state + EOT hysteresis. one bad client can't poison anyone else's
  inference.

  topic shape: `vad:stream:<caller_chosen_id>` — the channel doesn't
  care about the id; phoenix uses it as a routing handle.

  ## join params

      %{
        "silence_ms" => 700   # optional; ms of silence before :speech_end
                              # default 700
      }

  ## wire protocol

  the client pushes one window per message:

      push("audio", <<f32_samples::binary>>)   # 256 f32 le = 1024 bytes (8kHz)

  the server pushes one reply per window:

      push("frame", %{prob: 0.42})             # speech probability
      push("frame", %{prob: 0.91, event: "speech_start"})
      push("frame", %{prob: 0.05, event: "speech_end"})

  the `event` key is present only on transition frames. consumers that
  only care about EOT can subscribe to `"speech_end"` events and ignore
  per-frame `prob`.

  ## audio format

  silero in this build runs at 8kHz mono f32, 256 samples per window
  (32ms). this matches what ellie's call path uses (telnyx delivers
  G.711 μ-law @ 8kHz). consumers that have audio at other rates must
  resample on their side before pushing.

  wrong-size frames raise a reply with `{:error, :bad_window_size}` so
  the client knows immediately rather than silently producing garbage.
  """

  use Phoenix.Channel

  alias EllieAi.Calls.SileroVad
  alias EllieAi.Vad.Hysteresis

  require Logger

  # silero v5 @ 8khz: 256 samples per window. f32 = 4 bytes each.
  @window_size 256
  @window_bytes @window_size * 4
  @window_ms 32

  @impl true
  def join("vad:stream:" <> _id, params, socket) do
    silence_ms = parse_silence_ms(params)

    socket =
      socket
      |> assign(:rnn_state, SileroVad.initial_state())
      |> assign(:hysteresis, Hysteresis.new(silence_ms: silence_ms, window_ms: @window_ms))

    Logger.info("vad_channel join: silence_ms=#{silence_ms} topic=#{socket.topic}")

    {:ok, socket}
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "unknown topic"}}

  @impl true
  def handle_in("audio", {:binary, audio}, socket) when byte_size(audio) == @window_bytes do
    samples =
      for <<sample::little-float-32 <- audio>>, do: sample

    {prob, new_rnn} = SileroVad.infer(samples, socket.assigns.rnn_state)
    {new_hyst, events} = Hysteresis.feed(socket.assigns.hysteresis, prob)

    push(socket, "frame", payload_for(prob, events))

    {:noreply,
     socket
     |> assign(:rnn_state, new_rnn)
     |> assign(:hysteresis, new_hyst)}
  end

  def handle_in("audio", {:binary, audio}, socket) do
    {:reply,
     {:error,
      %{
        reason: "bad_window_size",
        expected_bytes: @window_bytes,
        got_bytes: byte_size(audio)
      }}, socket}
  end

  # any non-binary "audio" message is a protocol error on the caller's
  # side — we don't try to coerce json arrays into f32. send binary or
  # don't bother.
  def handle_in("audio", _payload, socket) do
    {:reply, {:error, %{reason: "audio must be a binary push"}}, socket}
  end

  # ── helpers ───────────────────────────────────────────────────────────

  defp payload_for(prob, []), do: %{prob: prob}

  defp payload_for(prob, [event | _]) do
    # at most one transition event per window, so emitting the first is
    # the same as emitting all. silero hysteresis never produces more.
    %{prob: prob, event: Atom.to_string(event)}
  end

  defp parse_silence_ms(%{"silence_ms" => ms}) when is_integer(ms) and ms > 0, do: ms
  defp parse_silence_ms(_), do: 700
end
