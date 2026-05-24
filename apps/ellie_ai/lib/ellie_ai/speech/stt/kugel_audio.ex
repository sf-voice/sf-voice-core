defmodule EllieAi.Speech.Stt.KugelAudio do
  @moduledoc """
  KugelAudio STT adapter — v1 STUB.

  API shape is unknown at v1 time; this module satisfies the
  `EllieAi.Speech.SttClient` behaviour so the modular backend's
  composition compiles. all entrypoints log + return `{:error, :not_implemented}`.

  config (when wired): `KUGEL_AUDIO_API_KEY`, `KUGEL_AUDIO_ENDPOINT`.
  """

  @behaviour EllieAi.Speech.SttClient

  require Logger

  @impl true
  def available? do
    !is_nil(System.get_env("KUGEL_AUDIO_API_KEY")) and
      !is_nil(System.get_env("KUGEL_AUDIO_ENDPOINT"))
  end

  @impl true
  def start(_opts) do
    Logger.warning("KugelAudio.start/1 not implemented (v1 stub)")
    {:error, :not_implemented}
  end

  @impl true
  def push_pcmu(_ref, _frame), do: {:error, :not_implemented}

  @impl true
  def flush_utterance(_ref), do: {:error, :not_implemented}

  @impl true
  def stop(_ref), do: :ok
end
