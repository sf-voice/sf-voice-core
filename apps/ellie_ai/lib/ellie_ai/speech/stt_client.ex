defmodule EllieAi.Speech.SttClient do
  @moduledoc """
  behaviour for a streaming speech-to-text client used by the modular
  audio backend. v1 ships one concrete impl: `EllieAi.Speech.Stt.KugelAudio`.

  callers feed μ-law (PCMU) frames in via `push_pcmu/2`; the impl emits
  partials + finalized utterances to a handler pid as messages of the
  form `{:stt_partial, ref, text}` and `{:stt_final, ref, text}`.
  """

  @type ref :: reference()
  @type opts :: keyword()

  @doc "true if the underlying API can be reached (config present)."
  @callback available?() :: boolean()

  @doc "open a streaming session. returns a ref that identifies messages from it."
  @callback start(opts()) :: {:ok, ref()} | {:error, term()}

  @doc "push a μ-law audio frame (8 kHz, mono)."
  @callback push_pcmu(ref(), binary()) :: :ok | {:error, term()}

  @doc "force-finalize the current utterance (e.g. on VAD silence)."
  @callback flush_utterance(ref()) :: :ok | {:error, term()}

  @doc "close the session."
  @callback stop(ref()) :: :ok
end
