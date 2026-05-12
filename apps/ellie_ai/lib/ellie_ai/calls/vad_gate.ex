defmodule EllieAi.Calls.VadGate do
  @moduledoc """
  per-call voice activity detector. one of these per active call,
  supervised by CallTree.

  receives μ-law audio chunks from CallServer (~20ms / 160 bytes each),
  decodes to float32 pcm, runs silero inference on 256-sample windows
  (32ms each), and runs a hysteresis state machine over the resulting
  speech-probability stream. emits `:speech_start` / `:speech_end` to
  CallServer at state transitions.

  hysteresis (canonical silero numbers):
    * silence → speech: prob ≥ 0.5 in a single window
    * speech → silence: prob < 0.35 sustained for ≥ 16 windows (~512 ms)

  sample buffering:
    telnyx delivers 160 samples per chunk; silero needs 256. we
    accumulate a tail of <256 samples between calls and flush as many
    full windows as fit each time.

  performance:
    one inference per 32 ms of audio = ~31 inferences/sec/call. silero
    on 256 samples is ~1-3ms on apple silicon. headroom is plenty for
    the v0 single-call demo. concurrent calls scale linearly until cpu.
  """

  use GenServer

  alias EllieAi.Calls.{CallRegistry, CallServer, Memory, SileroVad, Ulaw}

  require Logger

  # silero v5 8khz: 256 samples per inference window. each window is
  # 256 / 8000 = 32 ms.
  @window_size 256
  @window_ms 32

  # hysteresis thresholds (canonical silero numbers).
  @speech_threshold 0.5
  @silence_threshold 0.35

  # overridable per-org via vad_silence_ms setting. clamped so a /settings
  # typo can't make turns un-detectable or cut callers off mid-syllable.
  @default_silence_ms 700
  @min_silence_ms 200
  @max_silence_ms 3000

  defstruct [
    :ccid,
    :rnn_state,
    # how many low-prob windows must accumulate before declaring end of
    # turn. derived per-call at init from the org's `vad_silence_ms`
    # setting (or default). capped to a sane range.
    :min_silence_windows,
    sample_buffer: [],
    vad_state: :silence,
    silence_count: 0
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

  @doc """
  resolve the current process's `vad_silence_ms` setting (via Flag)
  into a window count, clamped to safe bounds. exposed for testing.
  """
  def silence_windows_now do
    ms = Memory.vad_silence_ms() |> clamp_silence_ms()
    div(ms, @window_ms)
  end

  @doc "default end-of-turn silence threshold (ms) when no per-org setting exists."
  def default_silence_ms, do: @default_silence_ms

  defp clamp_silence_ms(ms) when is_integer(ms),
    do: ms |> max(@min_silence_ms) |> min(@max_silence_ms)

  defp clamp_silence_ms(ms) when is_float(ms), do: clamp_silence_ms(round(ms))

  defp clamp_silence_ms(_), do: @default_silence_ms

  @doc "feed a μ-law audio chunk for analysis. async, non-blocking."
  def feed(ccid, mulaw_bytes) when is_binary(ccid) and is_binary(mulaw_bytes),
    do: CallRegistry.cast_to_vad_gate(ccid, {:feed, mulaw_bytes})

  # ── genserver ───────────────────────────────────────────────────────────

  @impl true
  def init(%{ccid: ccid}) do
    Logger.metadata(ccid: ccid)
    Memory.bootstrap_from(ccid)

    windows = silence_windows_now()
    Logger.info("vad_gate init: silence_windows=#{windows} (~#{windows * @window_ms}ms)")

    {:ok,
     %__MODULE__{
       ccid: ccid,
       rnn_state: SileroVad.initial_state(),
       min_silence_windows: windows
     }}
  end

  @impl true
  def handle_cast({:feed, mulaw_bytes}, state) do
    samples = Ulaw.decode_to_floats(mulaw_bytes)
    {:noreply, process_buffer(state, state.sample_buffer ++ samples)}
  end

  # not enough samples yet — stash and wait for more.
  defp process_buffer(state, buffer) when length(buffer) < @window_size do
    %{state | sample_buffer: buffer}
  end

  # at least one full window's worth — pull it off the front, run
  # inference, recurse on the remainder.
  defp process_buffer(state, buffer) do
    {window, rest} = Enum.split(buffer, @window_size)

    {prob, new_rnn_state} = SileroVad.infer(window, state.rnn_state)

    state
    |> Map.put(:rnn_state, new_rnn_state)
    |> apply_hysteresis(prob)
    |> process_buffer(rest)
  end

  # silence → speech: any single high-prob window flips us into speech.
  defp apply_hysteresis(%{vad_state: :silence} = state, prob)
       when prob >= @speech_threshold do
    Logger.info("vad: speech start (p=#{Float.round(prob, 3)})")
    CallServer.speech_start(state.ccid)
    %{state | vad_state: :speech, silence_count: 0}
  end

  # speech → silence: low-prob windows accumulate. only commit the
  # transition once `state.min_silence_windows` have stacked up. the
  # threshold is per-call (set at init from org's vad_silence_ms setting).
  defp apply_hysteresis(%{vad_state: :speech} = state, prob)
       when prob < @silence_threshold do
    new_count = state.silence_count + 1

    if new_count >= state.min_silence_windows do
      Logger.info(
        "vad: speech end (p=#{Float.round(prob, 3)}, sustained #{new_count * @window_ms}ms)"
      )

      CallServer.speech_end(state.ccid)
      %{state | vad_state: :silence, silence_count: 0}
    else
      %{state | silence_count: new_count}
    end
  end

  # any window above the silence threshold while we're in :speech resets
  # the silence counter.
  defp apply_hysteresis(%{vad_state: :speech} = state, _prob) do
    %{state | silence_count: 0}
  end

  # in :silence, sub-threshold windows are no-ops.
  defp apply_hysteresis(state, _prob), do: state
end
