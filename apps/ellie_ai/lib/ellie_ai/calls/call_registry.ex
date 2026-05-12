defmodule EllieAi.Calls.CallRegistry do
  @moduledoc """
  named registry for per-call processes. one entry per (kind, ccid) pair
  so the inbound media socket can find the call server, the call server
  can find its audio bridge, etc., without dragging pids through every
  message.

  named `CallRegistry` (not `Registry`) deliberately — using bare
  `Registry` would shadow the stdlib module inside this app's namespace
  and break call sites that need `Registry.register/3`, `Registry.lookup/2`,
  etc.

  the underlying stdlib registry is started under the same atom as this
  module so via-tuples are stable and short.
  """

  @registry __MODULE__

  @doc "child spec for the application supervisor."
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry)
  end

  @doc "via tuple for the call server keyed by ccid."
  def via_call_server(ccid), do: {:via, Registry, {@registry, {:call_server, ccid}}}

  @doc "via tuple for the audio bridge keyed by ccid."
  def via_audio_bridge(ccid), do: {:via, Registry, {@registry, {:audio_bridge, ccid}}}

  @doc "via tuple for the media-streaming socket keyed by ccid."
  def via_media_socket(ccid), do: {:via, Registry, {@registry, {:media_socket, ccid}}}

  @doc "via tuple for the per-call vad gate keyed by ccid."
  def via_vad_gate(ccid), do: {:via, Registry, {@registry, {:vad_gate, ccid}}}

  @doc "via tuple for the per-call archivist keyed by ccid."
  def via_archivist(ccid), do: {:via, Registry, {@registry, {:archivist, ccid}}}

  @doc "underlying stdlib registry name — for direct `Registry.register/3` calls."
  def name, do: @registry

  @doc "lookup the call-server pid for a ccid, nil if missing."
  def whereis_call_server(ccid), do: whereis({:call_server, ccid})

  @doc "lookup the audio-bridge pid for a ccid, nil if missing."
  def whereis_audio_bridge(ccid), do: whereis({:audio_bridge, ccid})

  @doc "lookup the media-streaming socket pid for a ccid, nil if missing."
  def whereis_media_socket(ccid), do: whereis({:media_socket, ccid})

  @doc "lookup the vad-gate pid for a ccid, nil if missing."
  def whereis_vad_gate(ccid), do: whereis({:vad_gate, ccid})

  @doc "lookup the archivist pid for a ccid, nil if missing."
  def whereis_archivist(ccid), do: whereis({:archivist, ccid})

  defp whereis(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # ── send/cast helpers ─────────────────────────────────────────────────
  #
  # collapse the "look up, send if alive, no-op if not" pattern that was
  # duplicated across 8 functions in AudioBridge / CallServer / VadGate /
  # Archivist. each helper names the target kind so callers don't repeat
  # the lookup boilerplate.

  @doc "send a raw message to the AudioBridge for ccid. websockex, not GenServer."
  def send_to_audio_bridge(ccid, message) do
    case whereis_audio_bridge(ccid) do
      pid when is_pid(pid) -> send(pid, message)
      nil -> :ok
    end

    :ok
  end

  @doc "GenServer.cast to the CallServer for ccid. no-op if missing."
  def cast_to_call_server(ccid, message) do
    case whereis_call_server(ccid) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      nil -> :ok
    end
  end

  @doc "GenServer.cast to the VadGate for ccid. no-op if missing."
  def cast_to_vad_gate(ccid, message) do
    case whereis_vad_gate(ccid) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      nil -> :ok
    end
  end

  @doc "GenServer.cast to the Archivist for ccid. no-op if missing."
  def cast_to_archivist(ccid, message) do
    case whereis_archivist(ccid) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      nil -> :ok
    end
  end
end
