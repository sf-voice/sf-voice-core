defmodule EllieAi.Calls.CallServer do
  @moduledoc """
  per-call orchestrator. routes audio between MediaStreamingSocket
  (telnyx ↔ us) and AudioBridge (us ↔ openai realtime). owns barge-in
  state, the outbound buffer, and the :ringing → :media_open → :hung_up
  state machine. hangups come from staff (`shutdown/1`) or telnyx; the
  model can't end calls anymore.
  """

  use GenServer

  alias EllieAi.Calls.{Archivist, AudioBridge, CallRegistry, Memory, VadGate}
  alias EllieAi.Telnyx.Client

  require Logger

  # 200 chunks ≈ 4s of μ-law @ 20ms/chunk — covers the bridge↔telnyx
  # startup gap. hitting this means something is structurally wrong.
  @outbound_buffer_cap 200

  @doc "barge-in confirmation window (ms); shorter is backchannel, longer fires response.cancel."
  def default_barge_in_cancel_ms, do: 400

  defstruct [
    :ccid,
    :state,
    :media_socket_pid,
    :start_payload,
    :hangup_reason,
    outbound_buffer: [],
    # barge-in: user_speaking? gates outbound audio; cancel_timer fires
    # response.cancel after the threshold (short bursts die on speech_end
    # first); did_cancel? decides commit-vs-resume on speech_end.
    user_speaking?: false,
    cancel_timer: nil,
    did_cancel?: false
  ]

  @doc "`:transient` — clean hangup exit doesn't trip the supervisor restart."
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: :transient,
      shutdown: 5_000
    }
  end

  def start_link(%{ccid: ccid} = args) when is_binary(ccid) do
    GenServer.start_link(__MODULE__, args, name: CallRegistry.via_call_server(ccid))
  end

  def media_started(pid, start_payload) when is_pid(pid) and is_map(start_payload) do
    GenServer.cast(pid, {:media_started, start_payload})
  end

  def audio_in(pid, mulaw_bytes) when is_pid(pid) and is_binary(mulaw_bytes) do
    GenServer.cast(pid, {:audio_in, mulaw_bytes})
  end

  def shutdown(pid) when is_pid(pid) do
    GenServer.cast(pid, :shutdown)
  end

  def register_media_socket(ccid, socket_pid) when is_binary(ccid) and is_pid(socket_pid),
    do: CallRegistry.cast_to_call_server(ccid, {:register_media_socket, socket_pid})

  def speech_start(ccid) when is_binary(ccid),
    do: CallRegistry.cast_to_call_server(ccid, :speech_start)

  def speech_end(ccid) when is_binary(ccid),
    do: CallRegistry.cast_to_call_server(ccid, :speech_end)

  def audio_out(ccid, mulaw_bytes) when is_binary(ccid) and is_binary(mulaw_bytes),
    do: CallRegistry.cast_to_call_server(ccid, {:audio_out, mulaw_bytes})

  @impl true
  def init(%{ccid: ccid, payload: payload}) do
    Memory.bootstrap_from(ccid)
    Logger.metadata(ccid: ccid, org: org_slug())
    Logger.info("call_server init")

    # sync (sub-ms local sqlite) — AudioBridge's session.update bakes the
    # customer into the prompt, no lookup_customer round trip.
    ensure_customer_sync(payload)

    # fire-and-forget — the network round-trip never blocks audio.
    # booking time has a second reconcile chance if this races or fails.
    spawn_resto_reconcile(payload)

    # render the system prompt into Memory; AudioBridge reads it at
    # session configure + every 13-min refresh.
    bootstrap_prompt()

    {:ok,
     %__MODULE__{
       ccid: ccid,
       state: :ringing,
       start_payload: payload
     }}
  end

  defp bootstrap_prompt do
    org = Memory.org()
    ccid = Memory.ccid()

    if org && is_binary(ccid) do
      try do
        EllieAi.Prompts.bootstrap_and_render!(org, ccid)
      rescue
        e -> Logger.warning("call_server: prompt bootstrap failed: #{Exception.message(e)}")
      end
    end

    :ok
  end

  defp ensure_customer_sync(payload) do
    org = Memory.org()
    from = payload["from"]

    if org && is_binary(from) and from != "" do
      case EllieAi.Customers.ensure_local(org, from) do
        {:ok, _row} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "call_server: ensure_local failed for from=#{from}: #{inspect(reason)}"
          )
      end
    end

    :ok
  end

  defp spawn_resto_reconcile(payload) do
    org = Memory.org()
    from = payload["from"]

    if org && is_binary(from) and from != "" do
      Task.start(fn ->
        case EllieAi.RestoClient.get_customer_by_phone(org, from) do
          {:ok, customer_payload} ->
            case EllieAi.Customers.reconcile_id(org, from, customer_payload) do
              {:ok, _row} ->
                :ok

              {:error, reason} ->
                Logger.warning(
                  "call_server: resto reconcile_id failed from=#{from}: #{inspect(reason)}"
                )
            end

          {:error, :not_found} ->
            # new to resto too — local stub keeps its ellie-minted id,
            # which we'll send to resto at booking.
            :ok

          {:error, reason} ->
            Logger.warning(
              "call_server: resto lookup failed from=#{from}: #{inspect(reason)}"
            )
        end
      end)
    end

    :ok
  end

  defp org_slug do
    case Memory.org() do
      %{slug: slug} -> slug
      _ -> "unknown"
    end
  end

  @impl true
  def handle_cast({:media_started, start_payload}, %{state: :ringing} = state) do
    Logger.info("media_started — codec=#{get_in(start_payload, ["media_format", "encoding"])}")
    {:noreply, %{state | state: :media_open, start_payload: start_payload}}
  end

  def handle_cast({:register_media_socket, pid}, state) do
    Process.monitor(pid)
    # arrival order preserved: appended on receipt, reversed on flush.
    state.outbound_buffer
    |> Enum.reverse()
    |> Enum.each(&send(pid, {:outbound_audio, &1}))

    if state.outbound_buffer != [] do
      Logger.info("flushed #{length(state.outbound_buffer)} buffered outbound chunks")
    end

    {:noreply, %{state | media_socket_pid: pid, outbound_buffer: []}}
  end

  def handle_cast({:audio_in, mulaw_bytes}, state) do
    # fan out to openai (input buffer), vad_gate (turn detection), archivist.
    AudioBridge.send_audio(state.ccid, mulaw_bytes)
    VadGate.feed(state.ccid, mulaw_bytes)
    Archivist.feed_inbound(state.ccid, mulaw_bytes)
    {:noreply, state}
  end

  def handle_cast(:speech_start, state) do
    cancel_ms = Memory.barge_in_cancel_ms()
    Logger.info("call_server: speech_start → mute (cancel armed for #{cancel_ms}ms)")
    timer = Process.send_after(self(), :maybe_cancel_response, cancel_ms)
    {:noreply, %{state | user_speaking?: true, cancel_timer: timer, did_cancel?: false}}
  end

  def handle_cast(:speech_end, state) do
    if state.cancel_timer, do: Process.cancel_timer(state.cancel_timer)

    if state.did_cancel? do
      Logger.info("call_server: speech_end → commit (real interruption)")
      AudioBridge.commit_and_respond(state.ccid)
    else
      Logger.info("call_server: speech_end → unmute (backchannel, no commit)")
    end

    {:noreply, %{state | user_speaking?: false, cancel_timer: nil, did_cancel?: false}}
  end

  # caller is speaking → drop outbound; recording stays aligned with what they heard.
  def handle_cast({:audio_out, _mulaw_bytes}, %{user_speaking?: true} = state) do
    {:noreply, state}
  end

  def handle_cast({:audio_out, mulaw_bytes}, %{media_socket_pid: pid} = state) when is_pid(pid) do
    send(pid, {:outbound_audio, mulaw_bytes})
    Archivist.feed_outbound(state.ccid, mulaw_bytes)
    {:noreply, state}
  end

  # socket not yet registered — buffer so the greeting isn't lost.
  def handle_cast({:audio_out, mulaw_bytes}, state) do
    # archive hears the greeting even if telnyx never accepts it.
    Archivist.feed_outbound(state.ccid, mulaw_bytes)

    if length(state.outbound_buffer) >= @outbound_buffer_cap do
      Logger.warning("outbound buffer full — dropping audio chunk; media socket never registered?")
      {:noreply, state}
    else
      {:noreply, %{state | outbound_buffer: [mulaw_bytes | state.outbound_buffer]}}
    end
  end

  def handle_cast({:hangup, reason}, state) do
    Logger.info("hangup requested: #{inspect(reason)}")
    Client.hangup(state.ccid)
    {:stop, :normal, %{state | state: :hung_up, hangup_reason: reason}}
  end

  def handle_cast(:shutdown, state) do
    Logger.info("shutdown — telnyx ended the call")
    {:stop, :normal, %{state | state: :hung_up}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{media_socket_pid: pid} = state) do
    Logger.warning("media socket went down — keeping call alive in case telnyx reconnects")
    {:noreply, %{state | media_socket_pid: nil}}
  end

  # only fires if the caller is still speaking; otherwise speech_end
  # already cancelled this timer (backchannel path).
  def handle_info(:maybe_cancel_response, %{user_speaking?: true} = state) do
    Logger.info("call_server: barge-in confirmed → cancel openai response")
    AudioBridge.cancel_response(state.ccid)
    {:noreply, %{state | did_cancel?: true, cancel_timer: nil}}
  end

  def handle_info(:maybe_cancel_response, state) do
    # speech_end won the race; no-op.
    {:noreply, %{state | cancel_timer: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("call_server unhandled info: #{inspect(msg)}")
    {:noreply, state}
  end
end
