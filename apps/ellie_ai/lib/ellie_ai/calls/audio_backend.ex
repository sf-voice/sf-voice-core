defmodule EllieAi.Calls.AudioBackend do
  @moduledoc """
  behaviour for the audio pipeline that turns a Telnyx call leg into a
  conversation. v1 ships with two implementations:

    * `EllieAi.Calls.AudioBackend.Realtime` — wraps the existing
      `AudioBridge` (Telnyx PCMU ↔ OpenAI Realtime, one WS).
    * `EllieAi.Calls.AudioBackend.Modular` — STT → LLM → TTS composition,
      v1 skeleton only (KugelAudio STT adapter is stubbed pending API).

  the `Scammer.Scripts.Script.backend` field picks one; the bootstrap
  call site (`Scammer.dial/2`) refuses unimplemented backends up front.

  this behaviour intentionally has no started/stopped/push callbacks for
  the Realtime impl — Realtime is driven by the existing CallTree
  children (`AudioBridge`, `VadGate`, `Archivist`) and selecting it is
  a no-op. only the modular backend needs the new wiring.
  """

  alias EllieAi.Scammer.Scripts.Script, as: S

  @doc "true if this backend can run a call right now (config + adapters reachable)."
  @callback available?() :: boolean()

  @doc "human-readable id."
  @callback id() :: atom()

  @doc """
  prepare per-call state for `ccid` running `script`. Realtime returns
  :ok and leans on Memory's `rendered_prompt` / `realtime_voice` that
  `Scammer.dial/2` already populated. Modular sets up its STT/LLM/TTS
  workers.
  """
  @callback prepare(ccid :: String.t(), S.t()) :: :ok | {:error, term()}

  @doc "resolve a backend module from a script field."
  @spec for(S.t()) :: module()
  def for(script) do
    case Map.get(script, :backend) do
      :realtime -> __MODULE__.Realtime
      :modular -> __MODULE__.Modular
    end
  end
end
