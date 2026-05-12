defmodule EllieAi.Calls.CallRegistry do
  @moduledoc """
  named registry for per-call processes, one entry per (kind, ccid).
  named `CallRegistry` deliberately — bare `Registry` would shadow the
  stdlib module in this namespace.
  """

  @registry __MODULE__

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry)
  end

  def via_call_server(ccid), do: {:via, Registry, {@registry, {:call_server, ccid}}}
  def via_audio_bridge(ccid), do: {:via, Registry, {@registry, {:audio_bridge, ccid}}}
  def via_media_socket(ccid), do: {:via, Registry, {@registry, {:media_socket, ccid}}}
  def via_vad_gate(ccid), do: {:via, Registry, {@registry, {:vad_gate, ccid}}}
  def via_archivist(ccid), do: {:via, Registry, {@registry, {:archivist, ccid}}}

  def name, do: @registry

  def whereis_call_server(ccid), do: whereis({:call_server, ccid})
  def whereis_audio_bridge(ccid), do: whereis({:audio_bridge, ccid})
  def whereis_media_socket(ccid), do: whereis({:media_socket, ccid})
  def whereis_vad_gate(ccid), do: whereis({:vad_gate, ccid})
  def whereis_archivist(ccid), do: whereis({:archivist, ccid})

  defp whereis(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # ── send/cast helpers (no-op if the target is missing) ───────────────

  @doc "raw send — AudioBridge is websockex, not GenServer."
  def send_to_audio_bridge(ccid, message) do
    case whereis_audio_bridge(ccid) do
      pid when is_pid(pid) -> send(pid, message)
      nil -> :ok
    end

    :ok
  end

  def cast_to_call_server(ccid, message) do
    case whereis_call_server(ccid) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      nil -> :ok
    end
  end

  def cast_to_vad_gate(ccid, message) do
    case whereis_vad_gate(ccid) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      nil -> :ok
    end
  end

  def cast_to_archivist(ccid, message) do
    case whereis_archivist(ccid) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      nil -> :ok
    end
  end
end
