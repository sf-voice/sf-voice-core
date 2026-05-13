defmodule EllieAi.Calls.VadGate do
  @moduledoc """
  per-call voice activity detector. decodes μ-law chunks (160 samples
  each) to f32 pcm, accumulates 256-sample windows, runs silero
  inference, and emits `:speech_start` / `:speech_end` over the shared
  hysteresis state machine in `EllieAi.Vad.Hysteresis`.

  the channel endpoint `EllieAiWeb.VadChannel` uses the same hysteresis
  module — see it for the canonical threshold/hangover behaviour.
  """

  use GenServer

  alias EllieAi.Calls.{CallRegistry, CallServer, Memory, SileroVad, Ulaw}
  alias EllieAi.Vad.Hysteresis

  require Logger

  # silero v5 @ 8khz: 256 samples per window = 32ms.
  @window_size 256
  @window_ms 32

  # clamped so a /settings typo can't kill turn detection.
  @default_silence_ms 700
  @min_silence_ms 200
  @max_silence_ms 3000

  defstruct [
    :ccid,
    :rnn_state,
    :hysteresis,
    sample_buffer: []
  ]

  # ── public api ──────────────────────────────────────────────────────────

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: :transient,
      shutdown: 5_000
    }
  end

  def start_link(%{ccid: ccid} = args) when is_binary(ccid) do
    GenServer.start_link(__MODULE__, args, name: CallRegistry.via_vad_gate(ccid))
  end

  def default_silence_ms, do: @default_silence_ms

  defp clamp_silence_ms(ms) when is_integer(ms),
    do: ms |> max(@min_silence_ms) |> min(@max_silence_ms)

  defp clamp_silence_ms(ms) when is_float(ms), do: clamp_silence_ms(round(ms))

  defp clamp_silence_ms(_), do: @default_silence_ms

  def feed(ccid, mulaw_bytes) when is_binary(ccid) and is_binary(mulaw_bytes),
    do: CallRegistry.cast_to_vad_gate(ccid, {:feed, mulaw_bytes})

  # ── genserver ───────────────────────────────────────────────────────────

  @impl true
  def init(%{ccid: ccid}) do
    Logger.metadata(ccid: ccid)
    Memory.bootstrap_from(ccid)

    silence_ms = Memory.vad_silence_ms() |> clamp_silence_ms()
    hysteresis = Hysteresis.new(silence_ms: silence_ms, window_ms: @window_ms)

    Logger.info(
      "vad_gate init: silence_ms=#{silence_ms} (windows=#{hysteresis.min_silence_windows})"
    )

    {:ok,
     %__MODULE__{
       ccid: ccid,
       rnn_state: SileroVad.initial_state(),
       hysteresis: hysteresis
     }}
  end

  @impl true
  def handle_cast({:feed, mulaw_bytes}, state) do
    samples = Ulaw.decode_to_floats(mulaw_bytes)
    {:noreply, process_buffer(state, state.sample_buffer ++ samples)}
  end

  defp process_buffer(state, buffer) when length(buffer) < @window_size do
    %{state | sample_buffer: buffer}
  end

  defp process_buffer(state, buffer) do
    {window, rest} = Enum.split(buffer, @window_size)

    {prob, new_rnn_state} = SileroVad.infer(window, state.rnn_state)
    {new_hysteresis, events} = Hysteresis.feed(state.hysteresis, prob)

    Enum.each(events, fn event -> emit(event, state.ccid, prob, new_hysteresis) end)

    %{state | rnn_state: new_rnn_state, hysteresis: new_hysteresis}
    |> process_buffer(rest)
  end

  defp emit(:speech_start, ccid, prob, _hyst) do
    Logger.info("vad: speech start (p=#{Float.round(prob, 3)})")
    CallServer.speech_start(ccid)
  end

  defp emit(:speech_end, ccid, prob, hyst) do
    Logger.info(
      "vad: speech end (p=#{Float.round(prob, 3)}, " <>
        "sustained #{hyst.min_silence_windows * @window_ms}ms)"
    )

    CallServer.speech_end(ccid)
  end
end
