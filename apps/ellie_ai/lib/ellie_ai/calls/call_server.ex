defmodule EllieAi.Calls.CallServer do
  @moduledoc """
  per-call orchestrator. holds call state and routes messages between:

    * MediaStreamingSocket (telnyx ↔ us, μ-law audio frames)
    * AudioBridge (us ↔ openai realtime, json events + g711_ulaw audio)
    * (later) VadGate, Archivist, Tool dispatch via Task.async_nolink

  state machine:

      :ringing           — call tree spawned, awaiting media stream
      :media_open        — telnyx media stream connected, audio flowing
      :hung_up           — terminal; the supervisor will tear us down

  hangups come from two paths: staff hitting "End call" in the UI
  (`Calls.end_call/1` → `shutdown/1`), or telnyx telling us the caller
  hung up. the model can no longer end the call itself — `end_call`
  was removed because it triggered too eagerly.
  """

  use GenServer

  alias EllieAi.Calls.{Archivist, AudioBridge, CallRegistry, Memory, VadGate}
  alias EllieAi.Telnyx.Client

  require Logger

  # cap on the outbound audio buffer (chunks). openai's response.audio.delta
  # arrives in ~20ms μ-law chunks (160 bytes each); 200 chunks = ~4s of
  # speech. plenty for the ~500ms gap between AudioBridge connecting and
  # MediaStreamingSocket receiving telnyx's `start` event. anything beyond
  # this means something is structurally wrong, not just slow.
  @outbound_buffer_cap 200

  @doc """
  default barge-in confirmation window (ms). caller speech sustained
  past this fires response.cancel; below this is treated as backchannel
  (gate handles the mute, openai's response is left alone).
  """
  def default_barge_in_cancel_ms, do: 400

  defstruct [
    :ccid,
    :state,
    :media_socket_pid,
    :start_payload,
    :hangup_reason,
    # outbound audio queued while media_socket_pid is nil. flushed in
    # arrival order on `register_media_socket`.
    outbound_buffer: [],
    # barge-in state. user_speaking? flips on vad speech_start/speech_end
    # and gates outbound audio. cancel_timer is the delayed `response.cancel`
    # — speech sustained past the threshold fires it; short bursts (cough,
    # mhm) don't. did_cancel? tracks whether THIS user turn triggered a
    # cancel, so we know whether to commit + request a fresh response on
    # speech_end (real interruption) vs. let the AI's in-flight response
    # resume after the mute (backchannel).
    user_speaking?: false,
    cancel_timer: nil,
    did_cancel?: false
  ]

  @doc """
  child spec — `:transient` so a clean exit on call hangup doesn't trip
  the supervisor's restart logic.
  """
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

  @doc "called by the inbound socket when the telnyx `start` event arrives."
  def media_started(pid, start_payload) when is_pid(pid) and is_map(start_payload) do
    GenServer.cast(pid, {:media_started, start_payload})
  end

  @doc "forward an inbound μ-law audio chunk into the call."
  def audio_in(pid, mulaw_bytes) when is_pid(pid) and is_binary(mulaw_bytes) do
    GenServer.cast(pid, {:audio_in, mulaw_bytes})
  end

  @doc "shut the call down cleanly (telnyx call.hangup or media stop)."
  def shutdown(pid) when is_pid(pid) do
    GenServer.cast(pid, :shutdown)
  end

  @doc "register the inbound socket pid so we can route outbound audio to it."
  def register_media_socket(ccid, socket_pid) when is_binary(ccid) and is_pid(socket_pid),
    do: CallRegistry.cast_to_call_server(ccid, {:register_media_socket, socket_pid})

  @doc "called by VadGate when speech onset is detected."
  def speech_start(ccid) when is_binary(ccid),
    do: CallRegistry.cast_to_call_server(ccid, :speech_start)

  @doc "called by VadGate when end-of-turn is detected."
  def speech_end(ccid) when is_binary(ccid),
    do: CallRegistry.cast_to_call_server(ccid, :speech_end)

  @doc "send outbound (openai → telnyx) audio bytes through the media socket."
  def audio_out(ccid, mulaw_bytes) when is_binary(ccid) and is_binary(mulaw_bytes),
    do: CallRegistry.cast_to_call_server(ccid, {:audio_out, mulaw_bytes})

  @impl true
  def init(%{ccid: ccid, payload: payload}) do
    Memory.bootstrap_from(ccid)
    Logger.metadata(ccid: ccid, org: org_slug())
    Logger.info("call_server init")

    # ensure a local customer_summary row exists for the caller before
    # AudioBridge starts. synchronous (local SQLite, sub-ms) so the
    # bridge's session.update can look up the customer and bake their
    # state into the prompt — model never has to call lookup_customer.
    ensure_customer_sync(payload)

    # ask resto whether it already knows this caller and reconcile our
    # local id with resto's if so. fire-and-forget — runs in its own
    # Task so the network round-trip never blocks the audio path.
    # booking time has a second reconcile chance if this one races or
    # fails transiently.
    spawn_resto_reconcile(payload)

    # fetch context (customer, history, reservations) + render the system
    # prompt into Memory. audio_bridge reads it from Memory at session
    # configure time and at every 13-min refresh.
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
        case EllieAi.Resto.get_customer_by_phone(org, from) do
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
            # caller is new to resto too — local stub keeps its ellie-minted
            # id, which we'll send to resto at booking.
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
    # flush any audio that arrived before the socket was ready. arrival
    # order is preserved: we append on receipt and reverse on flush.
    state.outbound_buffer
    |> Enum.reverse()
    |> Enum.each(&send(pid, {:outbound_audio, &1}))

    if state.outbound_buffer != [] do
      Logger.info("flushed #{length(state.outbound_buffer)} buffered outbound chunks")
    end

    {:noreply, %{state | media_socket_pid: pid, outbound_buffer: []}}
  end

  def handle_cast({:audio_in, mulaw_bytes}, state) do
    # fan out: openai needs the audio in its input buffer, vad_gate
    # needs it for turn-detection inference, archivist needs a copy
    # for the s3 recording. all three are async casts.
    AudioBridge.send_audio(state.ccid, mulaw_bytes)
    VadGate.feed(state.ccid, mulaw_bytes)
    Archivist.feed_inbound(state.ccid, mulaw_bytes)
    {:noreply, state}
  end

  # vad signals turn boundaries. speech_start gates outbound audio
  # immediately and schedules a delayed `response.cancel`; speech_end
  # un-gates and conditionally commits a new turn.
  #
  # the two-tier design (immediate mute, delayed cancel) means short
  # bursts like coughs or "mhm" backchannels gate the audio briefly
  # but don't kill the AI's in-flight response — the cancel timer
  # never fires because speech_end arrives first.
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

  # gate: caller is currently speaking → drop the outbound chunk (don't
  # send to telnyx, don't archive). the recording aligns with what the
  # caller actually heard.
  def handle_cast({:audio_out, _mulaw_bytes}, %{user_speaking?: true} = state) do
    {:noreply, state}
  end

  def handle_cast({:audio_out, mulaw_bytes}, %{media_socket_pid: pid} = state) when is_pid(pid) do
    send(pid, {:outbound_audio, mulaw_bytes})
    Archivist.feed_outbound(state.ccid, mulaw_bytes)
    {:noreply, state}
  end

  # outbound audio arrived before the socket is registered. buffer it so
  # the first ~hundreds of ms of greeting aren't lost. cap is generous —
  # if we hit it, something is structurally wrong (telnyx never connected).
  def handle_cast({:audio_out, mulaw_bytes}, state) do
    # the archive should hear the greeting even if telnyx never accepts it.
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

  # delayed barge-in cancel. only fires if the caller is still speaking
  # when the timer pops — anything shorter was a backchannel and the
  # speech_end handler already canceled this timer.
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
