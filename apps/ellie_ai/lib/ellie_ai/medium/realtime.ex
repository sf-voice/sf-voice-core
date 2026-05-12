defmodule EllieAi.Medium.Realtime do
  @moduledoc """
  """

  alias EllieAi.Providers.OpenAI

  @doc "url + headers for opening a realtime ws to the current provider."
  @spec connect_info() :: {:ok, String.t(), list()} | {:error, term()}
  def connect_info, do: OpenAI.connect_info()

  @doc "provider's preferred voice id for output audio."
  def voice, do: OpenAI.voice()

  @doc "model id for input transcription on the realtime stream."
  def transcription_model, do: OpenAI.transcription_model()

  @doc "wire format negotiated with the provider — μ-law for telephony."
  def audio_format, do: OpenAI.audio_format()
end
