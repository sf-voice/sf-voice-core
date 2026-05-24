defmodule EllieAi.Speech.TtsClient do
  @moduledoc """
  behaviour for a streaming text-to-speech client used by the modular
  audio backend. v1 ships one concrete impl: `EllieAi.Speech.Tts.ElevenLabs`.

  `synth_stream/2` returns a `Stream.t()` of μ-law (PCMU, 8 kHz, mono)
  binary frames suitable to write straight onto a Telnyx media stream.
  """

  @type opts :: [
          {:voice_id, String.t()}
          | {:model, String.t()}
          | {:stability, float()}
          | {:similarity_boost, float()}
        ]

  @callback available?() :: boolean()

  @callback synth_stream(String.t(), opts()) :: {:ok, Enumerable.t()} | {:error, term()}
end
