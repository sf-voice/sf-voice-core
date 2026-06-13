defmodule EllieAi.Calls.AudioBackend.Modular do
  @moduledoc """
  STT → LLM → TTS composition backend. v1 SKELETON ONLY.

  intended composition (when fully wired):

      Telnyx PCMU → VadGate → SttClient → LlmAdapter → TtsClient → Telnyx

  v1 status:
    * `Speech.Stt.KugelAudio` — stub pending API docs
    * `Speech.Tts.ElevenLabs` — stub, HTTP shape known but not wired
    * `Llm.Adapter.Anthropic` — stub, HTTP shape known but not wired

  `prepare/2` records an `audio_backend.modular.unavailable` system_event
  and returns `{:error, :not_implemented}`. `Scammer.dial/2` refuses
  modular scripts before reaching this code in v1 — this module exists
  so the behaviour contract is stable for future implementation.
  """

  @behaviour EllieAi.Calls.AudioBackend

  alias EllieAi.Calls, as: C
  alias EllieAi.Llm.Adapter.Anthropic, as: AnthropicAdapter
  alias EllieAi.Scammer.Scripts.Script
  alias EllieAi.Speech.Stt.KugelAudio, as: KA
  alias EllieAi.Speech.Tts.ElevenLabs, as: EL

  @impl true
  def available? do
    AnthropicAdapter.available?() and
      EL.available?() and
      KA.available?()
  end

  @impl true
  def id, do: :modular

  @impl true
  def prepare(ccid, %Script{id: script_id}) when is_binary(ccid) do
    C.record_system_event(
      ccid,
      "audio_backend",
      "audio_backend.modular.unavailable",
      "Modular backend is a v1 skeleton (script=#{script_id})",
      %{script: to_string(script_id)}
    )

    {:error, :not_implemented}
  end
end
