defmodule EllieAi.Vad.Hysteresis do
  @moduledoc """
  pure-function silero hysteresis state machine. takes per-window speech
  probabilities, emits `:speech_start` / `:speech_end` events with a
  silence-hangover so a single quiet window mid-utterance doesn't trigger
  end-of-turn prematurely.

  thresholds match silero's canonical recommendation (0.5 / 0.35); the
  silence-hangover is configurable so different consumers can tune
  end-of-turn aggressiveness without sharing a knob.

  two callers today: `EllieAi.Calls.VadGate` (turn detection during a
  live phone call) and `EllieAiWeb.VadChannel` (websocket endpoint
  consumed by the rust api). this module is the single source of truth
  for the state transitions; both wrappers translate the emitted events
  into their own side-effects.
  """

  # silero v5 canonical:
  #   silence → speech when prob ≥ @speech_threshold in one window
  #   speech → silence when prob < @silence_threshold sustained ≥ hangover
  @speech_threshold 0.5
  @silence_threshold 0.35

  defstruct vad_state: :silence,
            silence_count: 0,
            min_silence_windows: 0,
            window_ms: 32

  @type event :: :speech_start | :speech_end
  @type t :: %__MODULE__{
          vad_state: :silence | :speech,
          silence_count: non_neg_integer(),
          min_silence_windows: non_neg_integer(),
          window_ms: pos_integer()
        }

  @doc """
  build a fresh state. opts:

    * `:silence_ms` — milliseconds of sustained sub-threshold audio
      before `:speech_end` fires. converted internally to a window count.
      default 700ms.
    * `:window_ms` — duration of one inference window. silero v5 @ 8khz
      is 32ms; same model @ 16khz is also 32ms because it's 512 samples
      instead of 256. default 32.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    window_ms = Keyword.get(opts, :window_ms, 32)
    silence_ms = Keyword.get(opts, :silence_ms, 700)

    %__MODULE__{
      window_ms: window_ms,
      min_silence_windows: div(silence_ms, window_ms)
    }
  end

  @doc """
  feed one window's speech probability. returns `{new_state, events}`
  where `events` is `[]`, `[:speech_start]`, or `[:speech_end]`.
  """
  @spec feed(t(), float()) :: {t(), [event()]}
  def feed(%__MODULE__{vad_state: :silence} = s, prob) when prob >= @speech_threshold do
    {%{s | vad_state: :speech, silence_count: 0}, [:speech_start]}
  end

  def feed(%__MODULE__{vad_state: :speech} = s, prob) when prob < @silence_threshold do
    new_count = s.silence_count + 1

    if new_count >= s.min_silence_windows do
      {%{s | vad_state: :silence, silence_count: 0}, [:speech_end]}
    else
      {%{s | silence_count: new_count}, []}
    end
  end

  # in :speech, any window ≥ silence_threshold (but maybe < speech_threshold)
  # resets the silence counter — we're mid-utterance, not winding down.
  def feed(%__MODULE__{vad_state: :speech} = s, _prob) do
    {%{s | silence_count: 0}, []}
  end

  # in :silence, any window < speech_threshold is a no-op.
  def feed(%__MODULE__{vad_state: :silence} = s, _prob) do
    {s, []}
  end

  @doc "exposed for callers that want to log the canonical thresholds."
  def thresholds, do: %{speech: @speech_threshold, silence: @silence_threshold}
end
