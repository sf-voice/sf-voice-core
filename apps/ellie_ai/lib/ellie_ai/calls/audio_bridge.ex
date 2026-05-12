defmodule EllieAi.Calls.AudioBridge do
  @moduledoc """
  per-call websocket bridge to openai realtime. owns the session
  lifecycle (configure, 13-min refresh), routes inbound caller audio
  into openai and outbound model audio back to telnyx via CallServer,
  persists transcript turns, kicks off async sentiment scoring on user
  turns, and dispatches tool calls via `Tools.Catalog`.

  websockex pid is registered as `{:audio_bridge, ccid}` so siblings
  can reach it without holding a pid.
  """

  use WebSockex

  alias EllieAi.{Calls, Medium}
  alias EllieAi.Calls.{CallRegistry, CallServer, Constants, Memory}
  alias EllieAi.Tools.{Catalog, Tool}

  require Logger

  # 13min refresh — openai realtime sessions cap at 15min.
  @session_refresh_ms 13 * 60 * 1000

  # how long the bridge waits for a tool's execute/2 to return before
  # synthesising a transient error and unblocking openai. longer than
  # ~5s and the caller hears dead air.
  @tool_timeout_ms 5_000

  @fallback_prompt "you are ellie, a friendly host taking calls for a restaurant. greet the caller, then echo back what they say. let the caller hang up when they're done — we no longer end the call ourselves."

  def default_vad_mode, do: "silero"
  def tool_timeout_ms, do: @tool_timeout_ms

  @doc "server_vad config; used only when vad_mode == \"openai\" — otherwise VadGate drives turns."
  def server_vad_config do
    %{
      type: "server_vad",
      threshold: 0.5,
      prefix_padding_ms: 300,
      silence_duration_ms: 500
    }
  end

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: :transient,
      shutdown: 5_000
    }
  end

  def start_link(%{ccid: ccid}) when is_binary(ccid) do
    # bootstrap before reading config so Flag.* sees the call context.
    # start_link runs in the supervisor process; handle_connect bootstraps
    # again in the websocket process before any other code runs there.
    Memory.bootstrap_from(ccid)

    case {Memory.org(), Medium.Realtime.connect_info()} do
      {%_{} = org, {:ok, url, headers}} ->
        state = %{
          org: org,
          ccid: ccid,
          vad_mode: Memory.vad_mode(),
          response_in_flight: false,
          tx: %{first_logged: false, chunks: 0, bytes: 0},
          rx: %{first_logged: false, chunks: 0, bytes: 0}
        }

        WebSockex.start_link(url, __MODULE__, state,
          extra_headers: headers,
          name: CallRegistry.via_audio_bridge(ccid)
        )

      {nil, _} ->
        Logger.error("audio_bridge cannot start: no call context for ccid=#{ccid}")
        :ignore

      {_, {:error, :openai_api_key_missing}} ->
        # expected in dev/test where the key isn't set. prod boot is
        # gated by EnvCheck so this can't fire silently in prod.
        Logger.info("audio_bridge skipped: openai api key missing")
        :ignore

      {_, {:error, reason}} ->
        Logger.error("audio_bridge cannot start: #{inspect(reason)}")
        :ignore
    end
  end

  @doc "send a μ-law chunk to openai. async."
  def send_audio(ccid, mulaw_bytes) when is_binary(ccid) and is_binary(mulaw_bytes),
    do: CallRegistry.send_to_audio_bridge(ccid, {:tx_audio, mulaw_bytes})

  @doc "end of turn — drop if a response is already in flight."
  def commit_and_respond(ccid) when is_binary(ccid),
    do: CallRegistry.send_to_audio_bridge(ccid, :commit_and_respond)

  @doc "cancel openai's in-flight response (barge-in). optimistically clears response_in_flight."
  def cancel_response(ccid) when is_binary(ccid),
    do: CallRegistry.send_to_audio_bridge(ccid, :cancel_response)


  @impl true
  def handle_connect(_conn, state) do
    Logger.metadata(ccid: state.ccid, org: state.org.slug)
    Memory.bootstrap(state.org, state.ccid)
    Logger.info("audio_bridge connected to openai realtime (vad_mode=#{state.vad_mode})")
    send(self(), :configure_session)
    Process.send_after(self(), :refresh_session, @session_refresh_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:configure_session, state) do
    update = session_update(state.org, state.vad_mode, state.ccid)
    log_session_update(update)
    {:reply, {:text, Jason.encode!(update)}, state}
  end

  # all WS writes live in this process, so encode + counter bump stay together.
  def handle_info({:tx_audio, mulaw_bytes}, state) do
    frame =
      Jason.encode!(%{
        type: "input_audio_buffer.append",
        audio: Base.encode64(mulaw_bytes)
      })

    {:reply, {:text, frame}, bump_audio(state, :tx, byte_size(mulaw_bytes), "input_audio_buffer.append")}
  end

  def handle_info(:commit_and_respond, %{vad_mode: "openai"} = state) do
    Logger.debug("commit_and_respond ignored (vad_mode=openai)")
    {:ok, state}
  end

  def handle_info(:commit_and_respond, %{response_in_flight: true} = state) do
    Logger.debug("commit_and_respond dropped — response already in flight")
    {:ok, state}
  end

  def handle_info(:commit_and_respond, state) do
    frames = [
      Jason.encode!(%{type: "input_audio_buffer.commit"}),
      Jason.encode!(%{type: "response.create"})
    ]

    Logger.info("openai TX: input_audio_buffer.commit",
      direction: :tx,
      event_type: "input_audio_buffer.commit"
    )

    Logger.info("openai TX: response.create", direction: :tx, event_type: "response.create")

    send(self(), {:send_frame, hd(tl(frames))})
    {:reply, {:text, hd(frames)}, %{state | response_in_flight: true}}
  end

  def handle_info({:send_frame, frame}, state) do
    {:reply, {:text, frame}, state}
  end

  # barge-in: flip response_in_flight optimistically so the speech_end commit
  # fires. openai's response.canceled / done lands later and reconciles.
  def handle_info(:cancel_response, %{response_in_flight: false} = state) do
    Logger.debug("cancel_response: no response in flight, noop")
    {:ok, state}
  end

  def handle_info(:cancel_response, state) do
    frame = Jason.encode!(%{type: "response.cancel"})
    Logger.info("openai TX: response.cancel (barge-in)", direction: :tx, event_type: "response.cancel")
    {:reply, {:text, frame}, %{state | response_in_flight: false}}
  end

  # tool finished. persist (best-effort), then send function_call_output and
  # queue response.create. openai_call_id = openai's id (echoed back in
  # conversation.item.create.item.call_id); tool_call_id = our db row uuid.
  def handle_info({:tool_result, openai_call_id, tool_call_id, duration_ms, result}, state) do
    persist_tool_call_result(tool_call_id, result, duration_ms)

    output_frame =
      Jason.encode!(%{
        type: "conversation.item.create",
        item: %{
          type: "function_call_output",
          call_id: openai_call_id,
          output: encode_tool_output(result)
        }
      })

    send(self(), {:send_frame, Jason.encode!(%{type: "response.create"})})
    {:reply, {:text, output_frame}, %{state | response_in_flight: true}}
  end

  # proactive refresh: openai keeps the ws and just resets its context window.
  # our persisted transcript makes the cut invisible to staff.
  def handle_info(:refresh_session, state) do
    Logger.info("audio_bridge: 13min session refresh")
    Calls.record_system_event(state.ccid, "openai", "openai.session.refresh", "13min refresh fired", nil)

    update = session_update(state.org, state.vad_mode, state.ccid)
    log_session_update(update)
    Process.send_after(self(), :refresh_session, @session_refresh_ms)
    {:reply, {:text, Jason.encode!(update)}, state}
  end

  def handle_info(msg, state) do
    Logger.debug("audio_bridge unhandled info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, payload}, state) do
    case Jason.decode(payload) do
      {:ok, event} ->
        Logger.info("openai RX frame: type=#{event["type"]}",
          direction: :rx,
          event_type: event["type"]
        )

        handle_event(event, state)

      {:error, _} ->
        {:ok, state}
    end
  end

  def handle_frame({:close, code, reason}, state) do
    Logger.warning("audio_bridge close frame: code=#{code} reason=#{inspect(reason)}")
    {:ok, state}
  end

  def handle_frame(_other, state), do: {:ok, state}

  @impl true
  def handle_disconnect(%{reason: reason} = status, state) do
    # surface the http status from the upgrade so handshake failures aren't
    # masked as a generic `{:remote, :closed}`.
    extra =
      case status do
        %{conn: %{resp_status: s}} when is_integer(s) -> " http_status=#{s}"
        _ -> ""
      end

    Logger.warning("audio_bridge disconnected: #{inspect(reason)}#{extra}")

    Logger.info(
      "audio_bridge session summary: " <>
        "tx=#{state.tx.chunks} chunks/#{state.tx.bytes}b, " <>
        "rx=#{state.rx.chunks} chunks/#{state.rx.bytes}b"
    )

    {:ok, state}
  end


  defp log_session_update(%{session: s}) do
    tool_names = Enum.map(s.tools, & &1.name) |> Enum.join(",")
    voice = get_in(s, [:audio, :output, :voice])
    turn = get_in(s, [:audio, :input, :turn_detection])

    Logger.info(
      "openai TX: session.update model=#{EllieAi.Providers.OpenAI.realtime_model()} voice=#{voice} " <>
        "vad=#{vad_label(turn)} tools=[#{tool_names}] " <>
        "prompt_head=#{inspect(String.slice(s.instructions, 0, 200))}",
      direction: :tx,
      event_type: "session.update"
    )

    Logger.debug(fn ->
      "openai TX: session.update full_prompt=#{inspect(s.instructions)}"
    end)
  end

  defp vad_label(nil), do: "silero"
  defp vad_label(%{type: type}), do: type
  defp vad_label(_), do: "?"

  defp handle_event(%{"type" => "session.updated"}, state) do
    Logger.info("openai RX: session.updated — sending response.create for greeting",
      direction: :rx,
      event_type: "session.updated"
    )

    Calls.record_system_event(state.ccid, "openai", "openai.session.updated", "Session configured", nil)

    Logger.info("openai TX: response.create (greeting)",
      direction: :tx,
      event_type: "response.create"
    )

    {:reply, {:text, Jason.encode!(%{type: "response.create"})},
     %{state | response_in_flight: true}}
  end

  defp handle_event(%{"type" => "response.created"}, state) do
    Logger.info("openai RX: response.created", direction: :rx, event_type: "response.created")
    {:ok, %{state | response_in_flight: true}}
  end

  defp handle_event(%{"type" => "response.done"}, state) do
    Logger.info("openai RX: response.done", direction: :rx, event_type: "response.done")
    {:ok, %{state | response_in_flight: false}}
  end

  # GA renamed response.audio.* → response.output_audio.* (same shift as
  # modalities → output_modalities). preview models used the old names.
  defp handle_event(%{"type" => "response.output_audio.delta", "delta" => b64}, state)
       when is_binary(b64) do
    bytes =
      case Base.decode64(b64) do
        {:ok, mulaw} ->
          CallServer.audio_out(state.ccid, mulaw)
          byte_size(mulaw)

        :error ->
          0
      end

    {:ok, bump_audio(state, :rx, bytes, "response.output_audio.delta")}
  end

  defp handle_event(
         %{"type" => "response.output_audio_transcript.done", "transcript" => transcript},
         state
       )
       when is_binary(transcript) do
    Logger.info("openai RX: assistant said #{inspect(transcript)}",
      direction: :rx,
      event_type: "response.output_audio_transcript.done"
    )

    handle_transcript(state, :assistant, transcript)
    {:ok, state}
  end

  defp handle_event(
         %{
           "type" => "conversation.item.input_audio_transcription.completed",
           "transcript" => transcript
         },
         state
       )
       when is_binary(transcript) do
    Logger.info("openai RX: user said #{inspect(transcript)}",
      direction: :rx,
      event_type: "conversation.item.input_audio_transcription.completed"
    )

    handle_transcript(state, :user, transcript)
    {:ok, state}
  end

  # dispatch tool calls async so ws frames keep flowing while the tool runs.
  defp handle_event(
         %{
           "type" => "response.function_call_arguments.done",
           "call_id" => call_id,
           "name" => tool_name,
           "arguments" => args_json
         },
         state
       ) do
    dispatch_tool_call(call_id, tool_name, args_json, state)
    {:ok, state}
  end

  defp handle_event(%{"type" => "error"} = event, state) do
    Logger.error("openai realtime error: #{inspect(event)}")

    Calls.record_system_event(
      state.ccid,
      "openai",
      "openai.error",
      get_in(event, ["error", "message"]) || "OpenAI realtime error",
      event
    )

    {:ok, state}
  end

  defp handle_event(%{"type" => type} = event, state) do
    Logger.info("openai RX (unhandled): #{type} payload=#{inspect(event, limit: :infinity, printable_limit: 500)}",
      direction: :rx,
      event_type: type
    )

    {:ok, state}
  end

  defp handle_event(_event, state), do: {:ok, state}


  # unlinked Task with a deadline — a crash or hang can't wedge the bridge.
  # timeouts surface as a function_call_output the model can recover from.
  defp dispatch_tool_call(openai_call_id, tool_name, args_json, state) do
    self_pid = self()
    org = state.org
    started_at = System.monotonic_time(:millisecond)

    case {Jason.decode(args_json), find_tool(tool_name)} do
      {{:ok, args}, {:ok, module}} ->
        Logger.info(
          "tool dispatch: tool=#{tool_name} openai_call_id=#{openai_call_id} args=#{inspect(args, limit: 10)}"
        )

        tool_call_id = persist_pending_tool_call(state, tool_name, args, openai_call_id)

        spawn_supervised_tool(self_pid, openai_call_id, tool_call_id, tool_name, started_at, fn ->
          # ccid + tool_call_id let tools reach back into the call tree and
          # reference their own persisted row (replay flow).
          module.execute(args, %{org: org, ccid: state.ccid, tool_call_id: tool_call_id})
        end)

      {{:error, reason}, _} ->
        Logger.warning("tool args invalid json: tool=#{tool_name} reason=#{inspect(reason)}")

        # born in error state — never leaves a stale pending row in /calls/:id.
        tool_call_id =
          persist_failed_tool_call(
            state,
            tool_name,
            %{raw: args_json},
            openai_call_id,
            "invalid arguments json"
          )

        send(
          self_pid,
          {:tool_result, openai_call_id, tool_call_id, 0,
           {:error, {:permanent, "invalid arguments json"}}}
        )

      {_, {:error, _}} ->
        Logger.warning("unknown tool: #{tool_name}")

        tool_call_id =
          persist_failed_tool_call(state, tool_name, %{}, openai_call_id, "unknown tool")

        send(
          self_pid,
          {:tool_result, openai_call_id, tool_call_id, 0, {:error, {:permanent, "unknown tool"}}}
        )
    end
  end

  # outer spawn is an unlinked sentinel; the Task links only to it, so a
  # tool crash dies with the sentinel and the bridge keeps running.
  # tool_call_id may be nil (pending insert failed) — we still ship the
  # result so the caller hears a recovery.
  defp spawn_supervised_tool(
         bridge_pid,
         openai_call_id,
         tool_call_id,
         tool_name,
         started_at,
         fun
       ) do
    spawn(fn ->
      task =
        Task.async(fn ->
          try do
            fun.()
          rescue
            e -> {:error, {:permanent, Exception.message(e)}}
          catch
            :exit, reason -> {:error, {:permanent, "exited: #{inspect(reason)}"}}
          end
        end)

      timeout_ms = tool_timeout_ms()

      result =
        case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, result} ->
            result

          {:exit, reason} ->
            Logger.warning("tool crashed: tool=#{tool_name} reason=#{inspect(reason)}")
            {:error, {:permanent, "tool process crashed"}}

          nil ->
            Logger.warning(
              "tool timed out after #{timeout_ms}ms: tool=#{tool_name} openai_call_id=#{openai_call_id}"
            )

            {:error, {:transient, "tool timed out after #{timeout_ms}ms"}}
        end

      duration = System.monotonic_time(:millisecond) - started_at

      Logger.info(
        "tool result: tool=#{tool_name} duration_ms=#{duration} " <>
          "outcome=#{summarise_result(result)}"
      )

      send(bridge_pid, {:tool_result, openai_call_id, tool_call_id, duration, result})
    end)
  end

  # returns the row id, or nil if persistence failed. nil paths must not
  # break call flow — telemetry doesn't get to fail the conversation.
  defp persist_pending_tool_call(state, tool_name, args, openai_call_id) do
    case Calls.get_by_ccid(state.ccid) do
      nil ->
        nil

      call ->
        attrs = %{
          type: Calls.Constants.tool_call_type_midflight(),
          tool_name: tool_name,
          arguments: args,
          openai_call_id: openai_call_id
        }

        case Calls.start_tool_call(call.id, attrs) do
          {:ok, %{id: id}} -> id
          {:error, _} -> nil
        end
    end
  end

  # pre-dispatch failure path: insert + finish-error in one shot.
  defp persist_failed_tool_call(state, tool_name, args, openai_call_id, message) do
    id = persist_pending_tool_call(state, tool_name, args, openai_call_id)
    if id, do: Calls.finish_tool_call(id, {:error, message}, 0)
    id
  end

  # translate AudioBridge's outcome tuple into Calls.finish_tool_call/3's
  # contract. nil tool_call_id = persistence failed earlier, skip.
  defp persist_tool_call_result(nil, _result, _duration_ms), do: :ok

  defp persist_tool_call_result(tool_call_id, {:ok, payload}, duration_ms)
       when is_map(payload) do
    Calls.finish_tool_call(tool_call_id, {:ok, payload}, duration_ms)
  end

  defp persist_tool_call_result(tool_call_id, {:ok, payload}, duration_ms) do
    Calls.finish_tool_call(tool_call_id, {:ok, %{value: payload}}, duration_ms)
  end

  defp persist_tool_call_result(tool_call_id, {:error, {_class, message}}, duration_ms)
       when is_binary(message) do
    Calls.finish_tool_call(tool_call_id, {:error, message}, duration_ms)
  end

  defp persist_tool_call_result(tool_call_id, {:error, other}, duration_ms) do
    Calls.finish_tool_call(tool_call_id, {:error, inspect(other)}, duration_ms)
  end

  defp find_tool(name) do
    case Catalog.find(name) do
      nil -> {:error, :unknown_tool}
      module -> {:ok, module}
    end
  end

  defp tool_definitions do
    Enum.map(Catalog.all(), &Tool.to_openai/1)
  end

  # truncate payload so a chatty tool doesn't drown the log.
  defp summarise_result({:ok, payload}),
    do: "ok payload=#{inspect(payload, limit: 8, printable_limit: 200)}"

  defp summarise_result({:error, {class, reason}}),
    do: "error/#{class} reason=#{Tool.format_reason(reason)}"

  defp summarise_result({:error, reason}),
    do: "error reason=#{Tool.format_reason(reason)}"

  defp encode_tool_output({:ok, data}), do: Jason.encode!(data)

  defp encode_tool_output({:error, {:transient, reason}}),
    do: Jason.encode!(%{error: "transient", reason: Tool.format_reason(reason)})

  defp encode_tool_output({:error, {:permanent, reason}}),
    do: Jason.encode!(%{error: "permanent", reason: Tool.format_reason(reason)})

  defp encode_tool_output({:error, reason}),
    do: Jason.encode!(%{error: "unknown", reason: Tool.format_reason(reason)})


  defp session_update(%_{} = _org, vad_mode, ccid) do
    instructions = Memory.rendered_prompt(ccid) || @fallback_prompt

    %{
      type: "session.update",
      session: %{
        type: "realtime",
        instructions: instructions,
        output_modalities: ["audio"],
        audio: %{
          input: %{
            format: %{type: "audio/pcmu"},
            transcription: %{model: Medium.Realtime.transcription_model()},
            turn_detection: turn_detection_config(vad_mode)
          },
          output: %{
            format: %{type: "audio/pcmu"},
            voice: Medium.Realtime.voice()
          }
        },
        tools: tool_definitions(),
        tool_choice: "auto"
      }
    }
  end

  # we drive turn detection ourselves under silero; tell openai to stay out.
  defp turn_detection_config("silero"), do: nil
  defp turn_detection_config(_), do: server_vad_config()

  defp bump_audio(state, _direction, 0, _event_type), do: state

  defp bump_audio(state, direction, bytes, event_type) do
    counters = Map.fetch!(state, direction)

    counters =
      if counters.first_logged do
        counters
      else
        Logger.info(
          "openai #{direction_label(direction)}: first #{event_type} (#{bytes} bytes — subsequent chunks counted silently)",
          direction: direction,
          event_type: event_type
        )

        %{counters | first_logged: true}
      end

    Map.put(state, direction, %{
      counters
      | chunks: counters.chunks + 1,
        bytes: counters.bytes + bytes
    })
  end

  defp direction_label(:tx), do: "TX"
  defp direction_label(:rx), do: "RX"

  defp handle_transcript(state, source, transcript) do
    role =
      case source do
        :assistant -> Constants.role_assistant()
        :user -> Constants.role_user()
      end

    case Calls.append_turn(state.ccid, role, transcript) do
      {:ok, turn} ->
        if source == :user, do: EllieAi.Calls.Sentiment.score_async(turn)

      _ ->
        :ok
    end

  end
end
