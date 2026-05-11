defmodule EllieAi.Calls.AudioBridge do
  @moduledoc """
  wss://api.openai.com/v1/realtime
  """

  use WebSockex

  alias EllieAi.Calls
  alias EllieAi.Calls.{CallRegistry, CallServer, Constants}
  alias EllieAi.Orgs.Org
  alias EllieAi.{Prompts, Settings}
  alias EllieAi.Tools.Tool

  require Logger

  @default_model "gpt-realtime-2025-08-28"
  @default_voice "alloy"
  @default_vad_mode "silero"


  @tools [
    EllieAi.Tools.LookupCustomer
  ]

  @tool_timeout_ms 5_000

  @bye_regex ~r/\b(goodbye|bye[-\s]?bye|bye)\b/i
  @fallback_prompt "you are ellie, a friendly host taking calls for a restaurant. greet the caller, then echo back what they say. if they say goodbye, end the call politely."

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: :transient,
      shutdown: 5_000
    }
  end

  def start_link(%{org: %Org{} = org, ccid: ccid}) when is_binary(ccid) do
    case build_url_and_headers() do
      {:ok, url, headers} ->
        vad_mode = Settings.get_value(org.id, "vad_mode", @default_vad_mode)

        state = %{
          org: org,
          ccid: ccid,
          vad_mode: vad_mode,
          response_in_flight: false,
          tx: %{first_logged: false, chunks: 0, bytes: 0},
          rx: %{first_logged: false, chunks: 0, bytes: 0}
        }

        WebSockex.start_link(url, __MODULE__, state,
          extra_headers: headers,
          name: CallRegistry.via_audio_bridge(ccid)
        )

      {:error, reason} ->
        Logger.error("audio_bridge cannot start: #{inspect(reason)}")
        :ignore
    end
  end

  @doc """
  send a μ-law chunk to openai. async, non-blocking. routed as a message
  so the bridge process keeps owning the encode + counter bump.
  """
  def send_audio(ccid, mulaw_bytes) when is_binary(ccid) and is_binary(mulaw_bytes) do
    case CallRegistry.whereis_audio_bridge(ccid) do
      pid when is_pid(pid) -> send(pid, {:tx_audio, mulaw_bytes})
      nil -> :ok
    end
  end

  @doc """
  end of turn — drop if a response is already in flight.
  """
  def commit_and_respond(ccid) when is_binary(ccid) do
    case CallRegistry.whereis_audio_bridge(ccid) do
      pid when is_pid(pid) -> send(pid, :commit_and_respond)
      nil -> :ok
    end
  end


  @impl true
  def handle_connect(_conn, state) do
    Logger.metadata(ccid: state.ccid, org: state.org.slug)
    Logger.info("audio_bridge connected to openai realtime (vad_mode=#{state.vad_mode})")
    send(self(), :configure_session)
    {:ok, state}
  end

  @impl true
  def handle_info(:configure_session, state) do
    update = session_update(state.org, state.vad_mode)
    Logger.info("openai TX: session.update", direction: :tx, event_type: "session.update")
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

  # tool finished. send function_call_output, then a response.create
  def handle_info({:tool_result, call_id, result}, state) do
    output_frame =
      Jason.encode!(%{
        type: "conversation.item.create",
        item: %{
          type: "function_call_output",
          call_id: call_id,
          output: encode_tool_output(result)
        }
      })

    send(self(), {:send_frame, Jason.encode!(%{type: "response.create"})})
    {:reply, {:text, output_frame}, %{state | response_in_flight: true}}
  end

  def handle_info(msg, state) do
    Logger.debug("audio_bridge unhandled info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, payload}, state) do
    case Jason.decode(payload) do
      {:ok, event} -> handle_event(event, state)
      {:error, _} -> {:ok, state}
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


  defp handle_event(%{"type" => "session.updated"}, state) do
    Logger.info("openai RX: session.updated — sending response.create for greeting",
      direction: :rx,
      event_type: "session.updated"
    )

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

  defp handle_event(%{"type" => "response.audio.delta", "delta" => b64}, state)
       when is_binary(b64) do
    bytes =
      case Base.decode64(b64) do
        {:ok, mulaw} ->
          CallServer.audio_out(state.ccid, mulaw)
          byte_size(mulaw)

        :error ->
          0
      end

    {:ok, bump_audio(state, :rx, bytes, "response.audio.delta")}
  end

  defp handle_event(
         %{"type" => "response.audio_transcript.done", "transcript" => transcript},
         state
       )
       when is_binary(transcript) do
    Logger.info("openai RX: assistant said #{inspect(transcript)}",
      direction: :rx,
      event_type: "response.audio_transcript.done"
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
    {:ok, state}
  end

  defp handle_event(%{"type" => type} = event, state) do
    Logger.debug("openai RX (unhandled): #{type} #{inspect(event)}",
      direction: :rx,
      event_type: type
    )

    {:ok, state}
  end

  defp handle_event(_event, state), do: {:ok, state}


  # tools run in a nolinked task with a deadline so a crash or hang can't
  # wedge the bridge or openai's session. timeouts come back as a
  # function_call_output the model can recover from.
  defp dispatch_tool_call(call_id, tool_name, args_json, state) do
    self_pid = self()
    org = state.org
    started_at = System.monotonic_time(:millisecond)

    case {Jason.decode(args_json), find_tool(tool_name)} do
      {{:ok, args}, {:ok, module}} ->
        Logger.info(
          "tool dispatch: tool=#{tool_name} call_id=#{call_id} args=#{inspect(args, limit: 10)}"
        )

        spawn_supervised_tool(self_pid, call_id, tool_name, started_at, fn ->
          module.execute(args, %{org: org})
        end)

      {{:error, reason}, _} ->
        Logger.warning("tool args invalid json: tool=#{tool_name} reason=#{inspect(reason)}")
        send(self_pid, {:tool_result, call_id, {:error, {:permanent, "invalid arguments json"}}})

      {_, {:error, _}} ->
        Logger.warning("unknown tool: #{tool_name}")
        send(self_pid, {:tool_result, call_id, {:error, {:permanent, "unknown tool"}}})
    end
  end

  # outer spawn is a sentinel, unlinked from the bridge; the inner Task
  # only links to the sentinel, so a tool crash dies with the sentinel
  # and the bridge keeps running.
  defp spawn_supervised_tool(bridge_pid, call_id, tool_name, started_at, fun) do
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

      result =
        case Task.yield(task, @tool_timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, result} ->
            result

          {:exit, reason} ->
            Logger.warning("tool crashed: tool=#{tool_name} reason=#{inspect(reason)}")
            {:error, {:permanent, "tool process crashed"}}

          nil ->
            Logger.warning(
              "tool timed out after #{@tool_timeout_ms}ms: tool=#{tool_name} call_id=#{call_id}"
            )

            {:error, {:transient, "tool timed out after #{@tool_timeout_ms}ms"}}
        end

      duration = System.monotonic_time(:millisecond) - started_at
      Logger.info("tool result: tool=#{tool_name} call_id=#{call_id} duration_ms=#{duration}")
      send(bridge_pid, {:tool_result, call_id, result})
    end)
  end

  defp find_tool(name) do
    Enum.find_value(@tools, {:error, :unknown_tool}, fn module ->
      if module.name() == name, do: {:ok, module}, else: nil
    end)
  end

  defp tool_definitions do
    Enum.map(@tools, &Tool.to_openai/1)
  end

  defp encode_tool_output({:ok, data}), do: Jason.encode!(data)

  defp encode_tool_output({:error, {:transient, reason}}),
    do: Jason.encode!(%{error: "transient", reason: format_reason(reason)})

  defp encode_tool_output({:error, {:permanent, reason}}),
    do: Jason.encode!(%{error: "permanent", reason: format_reason(reason)})

  defp encode_tool_output({:error, reason}),
    do: Jason.encode!(%{error: "unknown", reason: format_reason(reason)})

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)


  defp session_update(%Org{} = org, vad_mode) do
    instructions =
      try do
        Prompts.render!(org.id, org: org)
      rescue
        _ -> @fallback_prompt
      end

    %{
      type: "session.update",
      session: %{
        modalities: ["audio", "text"],
        instructions: instructions,
        voice: @default_voice,
        input_audio_format: "g711_ulaw",
        output_audio_format: "g711_ulaw",
        input_audio_transcription: %{model: "whisper-1"},
        turn_detection: turn_detection_config(vad_mode),
        tools: tool_definitions(),
        tool_choice: "auto"
      }
    }
  end

  # we drive turn detection ourselves under silero; tell openai to stay out.
  defp turn_detection_config("silero"), do: nil

  defp turn_detection_config(_) do
    %{
      type: "server_vad",
      threshold: 0.5,
      prefix_padding_ms: 300,
      silence_duration_ms: 500
    }
  end

  defp build_url_and_headers do
    case System.get_env("OPENAI_API_KEY") do
      key when is_binary(key) and key != "" ->
        url = "wss://api.openai.com/v1/realtime?model=#{model()}"

        headers = [
          {"Authorization", "Bearer #{key}"},
          {"OpenAI-Beta", "realtime=v1"}
        ]

        {:ok, url, headers}

      _ ->
        {:error, :openai_api_key_missing}
    end
  end

  defp model do
    Application.get_env(:ellie_ai, __MODULE__, [])
    |> Keyword.get(:model, @default_model)
  end

  # matched phrase if a bye token sits on a word boundary, nil otherwise.
  # caller logs the phrase so we can spot false positives in prod.
  defp bye_match(transcript) when is_binary(transcript) do
    case Regex.run(@bye_regex, transcript) do
      [match | _] -> match
      _ -> nil
    end
  end

  defp bye_match(_), do: nil

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

    Calls.append_turn(state.ccid, role, transcript)

    case bye_match(transcript) do
      nil ->
        :ok

      phrase ->
        Logger.info("bye intent: source=#{source} phrase=#{inspect(phrase)} — hanging up")
        CallServer.bye_intent(state.ccid)
    end
  end
end
