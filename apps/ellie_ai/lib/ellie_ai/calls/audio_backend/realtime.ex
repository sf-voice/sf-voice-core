defmodule EllieAi.Calls.AudioBackend.Realtime do
  @moduledoc """
  default backend — runs through the existing `AudioBridge` →
  OpenAI Realtime pipeline. selection is a no-op: Memory already has the
  rendered prompt + voice from `Scammer.dial/2`, and the CallTree's
  AudioBridge picks them up via `session_update`.
  """

  @behaviour EllieAi.Calls.AudioBackend

  alias EllieAi.Scammer.Scripts.Script, as: ScScript

  @impl true
  def available?, do: true

  @impl true
  def id, do: :realtime

  @impl true
  def prepare(_ccid, _script), do: :ok
end
