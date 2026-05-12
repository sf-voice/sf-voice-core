defmodule EllieAi.Calls.VadGate do
  @moduledoc """
  per-call voice activity detector. decodes μ-law chunks (160 samples
  each) to f32 pcm, accumulates 256-sample windows, runs silero inference,
  and emits `:speech_start` / `:speech_end` over a hysteresis state machine.

  hysteresis (canonical silero):
    silence → speech: prob ≥ 0.5 in one window
    speech → silence: prob < 0.35 sustained ≥ min_silence_windows
  """

  use GenServer

  alias EllieAi.Calls.{CallRegistry, CallServer, Memory, SileroVad, Ulaw}

  require Logger

  # silero v5 @ 8khz: 256 samples per window = 32ms.
  @window_size 256
  @window_ms 32

  @speech_threshold 0.5
  @silence_threshold 0.35

  # clamped so a /settings typo can't kill turn detection.
  @default_silence_ms 700
  @min_silence_ms 200
  @max_silence_ms 3000

  defstruct [
    :ccid,
    :rnn_state,
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

  @doc "resolve this process's vad_silence_ms into a clamped window count. exposed for testing."
  def silence_windows_now do
    ms = Memory.vad_silence_ms() |> clamp_silence_ms()
    div(ms, @window_ms)
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

  defp process_buffer(state, buffer) when length(buffer) < @window_size do
    %{state | sample_buffer: buffer}
  end

  defp process_buffer(state, buffer) do
    {window, rest} = Enum.split(buffer, @window_size)

    {prob, new_rnn_state} = SileroVad.infer(window, state.rnn_state)

    state
    |> Map.put(:rnn_state, new_rnn_state)
    |> apply_hysteresis(prob)
    |> process_buffer(rest)
  end

  defp apply_hysteresis(%{vad_state: :silence} = state, prob)
       when prob >= @speech_threshold do
    Logger.info("vad: speech start (p=#{Float.round(prob, 3)})")
    CallServer.speech_start(state.ccid)
    %{state | vad_state: :speech, silence_count: 0}
  end

  # only commit speech → silence once min_silence_windows have stacked up.
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

  # any window above silence threshold resets the silence counter.
  defp apply_hysteresis(%{vad_state: :speech} = state, _prob) do
    %{state | silence_count: 0}
  end

  defp apply_hysteresis(state, _prob), do: state
end
