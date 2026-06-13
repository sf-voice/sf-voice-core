defmodule EllieAi.Speech.Tts.ElevenLabs do
  @moduledoc """
  ElevenLabs streaming TTS adapter for the modular audio backend. v1 STUB.

  ElevenLabs returns MP3/PCM via REST; the modular backend needs μ-law
  8 kHz. wiring requires either ElevenLabs's PCM 8 kHz output_format and a
  PCM→μ-law converter, or running their MP3 through a decoder. that
  conversion is the bulk of the implementation work and is deferred.

  config (when wired): `ELEVENLABS_API_KEY`.
  """

  @behaviour EllieAi.Speech.TtsClient

  require Logger

  @impl true
  def available? do
    not is_nil(System.get_env("ELEVENLABS_API_KEY"))
  end

  @impl true
  def synth_stream(text, _opts) when is_binary(text) do
    Logger.warning("ElevenLabs.synth_stream/2 not implemented (v1 stub)")
    {:error, :not_implemented}
  end
end
