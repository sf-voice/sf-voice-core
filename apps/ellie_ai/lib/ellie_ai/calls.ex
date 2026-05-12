defmodule EllieAi.Calls do
  @moduledoc """
  context for phone calls. owns:
    * the per-call supervision tree spawn/lookup entrypoints
    * persistence of calls + transcript turns (Call, TranscriptTurn schemas)

  call control id (`ccid`) is telnyx's durable per-leg identifier. we use
  it as the registry key so a webhook retry, a media-streaming reconnect,
  or any future cross-process lookup all converge on the same processes.
  the same id is the unique constraint on the `calls` table — webhook
  retries hit a get-or-create without inserting duplicate rows.
  """

  import Ecto.Query

  alias EllieAi.Calls.{
    Call,
    CallRegistry,
    CallServer,
    CallSupervisor,
    CallTree,
    Constants,
    SystemEvent,
    ToolCall,
    TranscriptTurn
  }

  alias EllieAi.Customers.CustomerSummary
  alias EllieAi.Orgs.Org
  alias EllieAi.Utils

  # inlined into the `append_turn/4` guard. guards reject runtime function
  # calls, so we read the canonical list once at compile time.
  @roles Constants.roles()
  alias EllieAi.Repo

  require Logger

  # ── supervision tree entrypoints ────────────────────────────────────────

  @doc """
  idempotent under telnyx webhook retries. also records the call row in
  the database so the staff /calls/:id page has data to show. returns
  `{:ok, pid}` whether freshly started or already running.
  """
  @spec spawn_or_noop(Org.t(), String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def spawn_or_noop(%Org{} = org, ccid, payload \\ %{}) when is_binary(ccid) do
    case CallRegistry.whereis_call_server(ccid) do
      pid when is_pid(pid) ->
        Logger.debug("calls.spawn_or_noop: existing tree for ccid=#{ccid}")
        {:ok, pid}

      nil ->
        Logger.info("calls.spawn_or_noop: starting new tree for ccid=#{ccid}")

        # record the call row first. if this fails we still spawn — a
        # missing row degrades the staff UI but doesn't block the call.
        case start_call(org.id, ccid, payload) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.warning("could not record call: #{inspect(reason)}")
        end

        spec = {CallTree, %{org: org, ccid: ccid, payload: payload}}

        case DynamicSupervisor.start_child(CallSupervisor, spec) do
          {:ok, _tree_pid} ->
            {:ok, CallRegistry.whereis_call_server(ccid)}

          {:error, {:already_started, _}} ->
            {:ok, CallRegistry.whereis_call_server(ccid)}

          {:error, reason} = err ->
            Logger.error("calls.spawn_or_noop failed for ccid=#{ccid}: #{inspect(reason)}")
            err
        end
    end
  end

  @doc "invoked by the websocket transport once telnyx's `start` event arrives."
  @spec on_media_started(String.t(), map()) :: :ok
  def on_media_started(ccid, start_payload) when is_binary(ccid) do
    update_status(ccid, Constants.status_active())

    case CallRegistry.whereis_call_server(ccid) do
      pid when is_pid(pid) -> CallServer.media_started(pid, start_payload)
      nil -> :ok
    end
  end

  @spec on_inbound_audio(String.t(), binary()) :: :ok
  def on_inbound_audio(ccid, mulaw_bytes) when is_binary(ccid) and is_binary(mulaw_bytes) do
    case CallRegistry.whereis_call_server(ccid) do
      pid when is_pid(pid) -> CallServer.audio_in(pid, mulaw_bytes)
      nil -> :ok
    end
  end

  @doc """
  terminates the entire CallTree so every child's `terminate/2` runs —
  most importantly Archivist's, which is what finalises the wav and
  uploads to s3. without this, normal-exit of CallServer would leave the
  siblings alive and Archivist would never flush.
  """
  @spec on_hangup(String.t()) :: :ok
  def on_hangup(ccid) when is_binary(ccid) do
    finish_call(ccid, Constants.status_ended(), nil)
    # async post-call summary. snapshots call_id before teardown drops
    # the registry entry. failures inside the Task log but don't block.
    case get_by_ccid(ccid) do
      %Call{id: call_id} -> EllieAi.Calls.Summarizer.summarize_async(call_id)
      nil -> :ok
    end

    terminate_tree(ccid)
  end

  @doc """
  tells telnyx to drop the actual call leg, then mirrors the same DB +
  process teardown as `on_hangup/1` so the UI doesn't have to wait for
  telnyx's call.hangup webhook to round-trip. hangup_reason
  `"ended_by_staff"` distinguishes these from caller-side endings.

  telnyx hangup errors are logged but not surfaced — staff intent is
  "make this stop now". if telnyx's API is unreachable we still tear
  down our side so the AI stops responding.
  """
  @spec end_call(String.t()) :: :ok
  def end_call(ccid) when is_binary(ccid) do
    case EllieAi.Telnyx.Client.hangup(ccid) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("end_call: telnyx hangup failed ccid=#{ccid} reason=#{inspect(reason)}")
    end

    finish_call(ccid, Constants.status_ended(), "ended_by_staff")

    case get_by_ccid(ccid) do
      %Call{id: call_id} -> EllieAi.Calls.Summarizer.summarize_async(call_id)
      nil -> :ok
    end

    terminate_tree(ccid)
  end

  # take down the whole per-call tree. each child's `terminate/2` runs in
  # reverse-start order, so Archivist (last) gets its 15s shutdown window
  # to flush the wav + upload to s3 before the supervisor force-kills it.
  # also drops the shared context row so the ETS table doesn't leak.
  defp terminate_tree(ccid) when is_binary(ccid) do
    result =
      case :global.whereis_name({CallTree, ccid}) do
        :undefined ->
          :ok

        pid when is_pid(pid) ->
          DynamicSupervisor.terminate_child(CallSupervisor, pid)
          :ok
      end

    EllieAi.Calls.Memory.drop_context(ccid)
    result
  end

  # ── persistence ─────────────────────────────────────────────────────────

  @doc """
  idempotent — duplicate ccid (telnyx webhook retry) returns the
  existing row instead of an error. `payload` is the telnyx
  call.initiated webhook payload.
  """
  @spec start_call(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, Call.t()} | {:error, Ecto.Changeset.t()}
  def start_call(org_id, ccid, payload) when is_binary(org_id) and is_binary(ccid) do
    case get_by_ccid(ccid) do
      nil ->
        from_phone = payload["from"]
        to_phone = payload["to"]
        # phone match is the only lookup we have at call.initiated time.
        # nil is fine — the customer FK gets stamped later when UpsertCustomer
        # or ensure_local creates the row, via maybe_stamp_customer_id/2.
        customer_id = resolve_customer_id(org_id, from_phone)

        result =
          %Call{}
          |> Call.changeset(%{
            org_id: org_id,
            customer_id: customer_id,
            provider: "telnyx",
            provider_id: ccid,
            channel_id: Constants.channel_id(from_phone || "unknown", to_phone || "unknown"),
            from_phone: from_phone,
            to_phone: to_phone,
            status: Constants.status_ringing(),
            started_at: now()
          })
          |> Repo.insert()

        case result do
          {:ok, _} = ok ->
            broadcast_call_changed(ok)
            ok

          {:error, %Ecto.Changeset{errors: errors}} = err ->
            # race: a parallel webhook retry won the insert between our
            # get_by_ccid/1 miss and Repo.insert. re-fetch and return the
            # winner's row. no broadcast — the winner already fired one.
            if Keyword.has_key?(errors, :provider_id) do
              case get_by_ccid(ccid) do
                %Call{} = existing -> {:ok, existing}
                nil -> err
              end
            else
              err
            end
        end

      %Call{} = existing ->
        {:ok, existing}
    end
  end

  @doc """
  refuses to write if the call has already been finished (`ended_at`
  set). without that guard an out-of-order `on_media_started` arriving
  after `on_hangup` would revert the row to "active" and the homepage
  would show a phantom live call for the rest of the session.
  """
  @spec update_status(String.t(), String.t()) :: :ok
  def update_status(ccid, status) when is_binary(ccid) and is_binary(status) do
    prev_call = get_by_ccid(ccid)
    now = now()

    # atomic conditional write: the `is_nil(ended_at)` guard lives in the
    # WHERE clause so an out-of-order media_started after hangup can't
    # revert a finished call. rowcount tells us which branch we took.
    {count, _} =
      from(c in Call, where: c.provider_id == ^ccid and is_nil(c.ended_at))
      |> Repo.update_all(set: [status: status, updated_at: now])

    case {prev_call, count} do
      {nil, _} ->
        :ok

      {%Call{status: prev}, 1} ->
        log_status_change(ccid, prev, status, :update_status)
        broadcast_call_changed({:ok, get_by_ccid(ccid)})

      {%Call{status: prev}, 0} ->
        Logger.info(
          "call status change refused — call already ended " <>
            "ccid=#{ccid} attempted=#{status} stored=#{prev}"
        )
    end

    :ok
  end

  defp log_status_change(ccid, prev, new, source) do
    require Logger
    Logger.info("call status change ccid=#{ccid} #{prev} -> #{new} source=#{source}")
  end

  @doc "no-op if the call doesn't exist (cleanup race)."
  @spec finish_call(String.t(), String.t(), String.t() | nil) :: :ok
  def finish_call(ccid, status, hangup_reason) when is_binary(ccid) and is_binary(status) do
    prev_call = get_by_ccid(ccid)
    now = now()

    # atomic conditional finish: the `is_nil(ended_at)` guard lives in the
    # WHERE clause so a webhook retry or duplicate stop event can't
    # double-finish (and overwrite hangup_reason / ended_at).
    {count, _} =
      from(c in Call, where: c.provider_id == ^ccid and is_nil(c.ended_at))
      |> Repo.update_all(
        set: [
          status: status,
          hangup_reason: hangup_reason,
          ended_at: now,
          updated_at: now
        ]
      )

    case {prev_call, count} do
      {nil, _} ->
        :ok

      {%Call{status: prev}, 1} ->
        log_status_change(ccid, prev, status, :finish_call)
        broadcast_call_changed({:ok, get_by_ccid(ccid)})

      {%Call{}, 0} ->
        Logger.debug("finish_call no-op — already ended ccid=#{ccid}")
    end

    :ok
  end

  @doc """
  role is "user" or "assistant". no-op if the call row hasn't been
  created yet (audio briefly outraces spawn — rare but possible).
  """
  @spec append_turn(String.t(), String.t(), String.t(), map()) ::
          {:ok, TranscriptTurn.t()} | {:error, term()}
  def append_turn(ccid, role, text, attrs \\ %{})
      when is_binary(ccid) and role in @roles and is_binary(text) do
    case get_by_ccid(ccid) do
      nil ->
        {:error, :no_call}

      %Call{id: call_id} ->
        ts = now()

        # canonical fields win over `attrs` — callers can pass extras (e.g.
        # provider metadata) but cannot override the call_id, role, text, or
        # timestamps that this function is responsible for.
        merged =
          Map.merge(attrs, %{
            call_id: call_id,
            role: role,
            text: text,
            started_at: ts,
            ended_at: ts
          })

        result =
          %TranscriptTurn{}
          |> TranscriptTurn.changeset(merged)
          |> Repo.insert()

        case result do
          {:ok, _turn} ->
            # mirror into Memory and re-render the system prompt so the
            # rolling transcript flows back into openai's next session.update.
            EllieAi.Calls.Memory.append_turn(ccid, role, text, ts)
            EllieAi.Prompts.re_render!(ccid)

            Phoenix.PubSub.broadcast(
              EllieAi.PubSub,
              "calls:lifecycle:#{call_id}",
              {:call_changed, %{event: :turn_appended, call_id: call_id}}
            )

          _ ->
            :ok
        end

        result
    end
  end

  # ── sms ─────────────────────────────────────────────────────────────────

  @doc """
  thin wrapper over `append_turn/4` that stamps `medium: "sms"`. used by
  the inbound webhook (role `"user"`) and the staff composer (role
  `"staff"`).
  """
  @spec append_sms_turn(String.t(), String.t(), String.t(), map()) ::
          {:ok, TranscriptTurn.t()} | {:error, term()}
  def append_sms_turn(ccid, role, text, attrs \\ %{}) do
    append_turn(ccid, role, text, Map.put(attrs, :medium, Constants.medium_sms()))
  end

  @doc """
  finds the most recent call for `from_phone` in `org_id` and appends a
  user/sms turn. drops the message with a log line if no parent call
  exists — sms-only contacts aren't supported yet.
  """
  @spec ingest_inbound_sms(Ecto.UUID.t(), String.t(), String.t(), String.t()) ::
          {:ok, TranscriptTurn.t()} | {:error, term()}
  def ingest_inbound_sms(org_id, from_phone, text, to_phone)
      when is_binary(org_id) and is_binary(from_phone) and is_binary(text) and is_binary(to_phone) do
    # canonical key: tel_<caller>_<callee>. matches start_call/3's stamp
    # so we don't have to phone-string-match across rows.
    channel_id = Constants.channel_id(from_phone, to_phone)

    case find_recent_call_by_channel(org_id, channel_id) do
      %Call{provider_id: ccid} ->
        append_sms_turn(ccid, Constants.role_user(), text)

      nil ->
        require Logger

        Logger.warning(
          "sms ingest: no recent call for channel=#{channel_id} org=#{org_id}; dropping"
        )

        {:error, :no_parent_call}
    end
  end

  defp find_recent_call_by_channel(org_id, channel_id) do
    from(c in Call,
      where: c.org_id == ^org_id and c.channel_id == ^channel_id,
      order_by: [desc: c.started_at],
      limit: 1
    )
    |> Repo.one()
  end

  # phone -> customer_id resolution used by start_call/3. nil is a valid
  # outcome — the FK is nullable and gets stamped later via stamp_customer_id/2.
  defp resolve_customer_id(_org_id, nil), do: nil
  defp resolve_customer_id(_org_id, ""), do: nil

  defp resolve_customer_id(org_id, phone) when is_binary(phone) do
    case Repo.get_by(CustomerSummary, org_id: org_id, phone_e164: phone) do
      %CustomerSummary{id: id} -> id
      nil -> nil
    end
  end

  @doc """
  stamps `customer_id` onto any of an org's calls that match `phone` but
  haven't been linked yet. called from UpsertCustomer / ensure_local
  after a customer row appears so the FK back-fills mid-call.
  """
  @spec stamp_customer_id(Ecto.UUID.t(), String.t(), Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def stamp_customer_id(org_id, phone, customer_id)
      when is_binary(org_id) and is_binary(phone) and is_binary(customer_id) do
    from(c in Call,
      where: c.org_id == ^org_id and c.from_phone == ^phone and is_nil(c.customer_id)
    )
    |> Repo.update_all(set: [customer_id: customer_id])
  end

  @doc """
  preloads transcript_turns so the customer page can render the unified
  conversation feed without N+1 queries.
  """
  @spec list_for_customer(Ecto.UUID.t()) :: [Call.t()]
  def list_for_customer(customer_id) when is_binary(customer_id) do
    from(c in Call,
      where: c.customer_id == ^customer_id,
      order_by: [desc: c.started_at],
      preload: [transcript_turns: ^from(t in TranscriptTurn, order_by: [asc: t.inserted_at])]
    )
    |> Repo.all()
  end

  @doc """
  called by Summarizer after the gpt-4o-mini round-trip; no-op if the
  row was deleted.
  """
  @spec set_summary(Ecto.UUID.t(), String.t()) :: :ok
  def set_summary(call_id, summary) when is_binary(call_id) and is_binary(summary) do
    case Repo.get(Call, call_id) do
      nil ->
        :ok

      %Call{} = call ->
        call
        |> Call.changeset(%{summary: summary})
        |> Repo.update()
        |> case do
          {:ok, _} ->
            broadcast_call_changed({:ok, call})
            :ok

          {:error, reason} ->
            require Logger

            Logger.warning(
              "calls.set_summary failed call_id=#{call_id} reason=#{inspect(reason)}"
            )

            :ok
        end
    end
  end

  # ── tool_calls ──────────────────────────────────────────────────────────

  @doc """
  inserts a `pending` tool_call row at the moment of dispatch and hands
  back a `%ToolCall{}` so `finish_tool_call/4` can target the right row.

  `attrs` shape:
    * `:type`             required — `before` | `midflight` | `after`
    * `:tool_name`        required — e.g. `"lookup_customer"`
    * `:arguments`        map (defaults to %{})
    * `:openai_call_id`   required for midflight; nil for before/after
    * `:replayed_from_id` optional — set when this is a replay of an
                          earlier tool_call
  """
  @spec start_tool_call(Ecto.UUID.t(), map()) ::
          {:ok, ToolCall.t()} | {:error, Ecto.Changeset.t()}
  def start_tool_call(call_id, attrs) when is_binary(call_id) and is_map(attrs) do
    attrs =
      attrs
      |> Map.put(:call_id, call_id)
      |> Map.put_new(:status, Constants.tool_call_status_pending())
      |> Map.put_new(:arguments, %{})

    %ToolCall{}
    |> ToolCall.changeset(attrs)
    |> Repo.insert()
    |> tap_broadcast_tool_call_changed()
  end

  @doc """
  mark a tool_call terminal. `outcome` is `{:ok, result}` (result is a
  map serialised to json) or `{:error, message}` (string). `duration_ms`
  is wall-clock ms from dispatch to result.

  the underlying row is found by `id`. returns `{:ok, tool_call}` on
  success or `{:error, changeset | :not_found}`.
  """
  @spec finish_tool_call(
          Ecto.UUID.t(),
          {:ok, map()} | {:error, String.t()},
          non_neg_integer()
        ) ::
          {:ok, ToolCall.t()} | {:error, term()}
  def finish_tool_call(tool_call_id, outcome, duration_ms)
      when is_binary(tool_call_id) and is_integer(duration_ms) and duration_ms >= 0 do
    case Repo.get(ToolCall, tool_call_id) do
      nil ->
        {:error, :not_found}

      %ToolCall{} = row ->
        attrs = outcome_attrs(outcome) |> Map.put(:duration_ms, duration_ms)

        row
        |> ToolCall.changeset(attrs)
        |> Repo.update()
        |> tap_broadcast_tool_call_changed()
    end
  end

  defp outcome_attrs({:ok, result}) when is_map(result) do
    %{status: Constants.tool_call_status_ok(), result: result, error: nil}
  end

  defp outcome_attrs({:error, message}) when is_binary(message) do
    %{status: Constants.tool_call_status_error(), error: message, result: nil}
  end

  @doc "oldest first. drives the staff /calls/:id timeline."
  @spec list_tool_calls(Ecto.UUID.t()) :: [ToolCall.t()]
  def list_tool_calls(call_id) when is_binary(call_id) do
    from(t in ToolCall,
      where: t.call_id == ^call_id,
      order_by: [asc: t.inserted_at]
    )
    |> Repo.all()
  end

  @spec get_tool_call(Ecto.UUID.t()) :: ToolCall.t() | nil
  def get_tool_call(id) when is_binary(id), do: Repo.get(ToolCall, id)

  @doc """
  inserts a new `tool_calls` row tagged `replayed_from_id: <original id>`
  — the original is never mutated so the timeline shows both attempts.
  transient tool errors are surfaced on the new row as `error` with the
  message. `args_override` is optional; if nil the original arguments
  are reused verbatim.
  """
  @spec replay_tool_call(Ecto.UUID.t(), map() | nil) ::
          {:ok, ToolCall.t()} | {:error, term()}
  def replay_tool_call(tool_call_id, args_override) when is_binary(tool_call_id) do
    with %ToolCall{} = original <- Repo.get(ToolCall, tool_call_id),
         %Call{} = call <- Repo.get(Call, original.call_id),
         call = Repo.preload(call, :org),
         module when not is_nil(module) <-
           EllieAi.Tools.Catalog.find(original.tool_name),
         args = if(is_map(args_override), do: args_override, else: original.arguments),
         ccid = call.provider_id,
         {:ok, new_row} <-
           start_tool_call(call.id, %{
             type: original.type,
             tool_name: original.tool_name,
             arguments: args,
             openai_call_id: nil,
             replayed_from_id: original.id
           }) do
      started_at = System.monotonic_time(:millisecond)

      outcome =
        try do
          module.execute(Utils.stringify_keys(args), %{
            org: call.org,
            ccid: ccid,
            tool_call_id: new_row.id
          })
        rescue
          e -> {:error, {:permanent, Exception.message(e)}}
        end

      duration = System.monotonic_time(:millisecond) - started_at

      case outcome do
        {:ok, payload} ->
          finish_tool_call(new_row.id, {:ok, normalise_payload(payload)}, duration)

        {:error, {_class, message}} when is_binary(message) ->
          finish_tool_call(new_row.id, {:error, message}, duration)

        {:error, other} ->
          finish_tool_call(new_row.id, {:error, inspect(other)}, duration)
      end
    else
      nil -> {:error, :not_found}
      other -> other
    end
  end

  defp normalise_payload(p) when is_map(p), do: p
  defp normalise_payload(p), do: %{value: p}

  @doc """
  midflight path: find the pending row AudioBridge inserted on dispatch
  so we can update it when openai delivers the result frame.
  """
  @spec get_tool_call_by_openai_id(String.t()) :: ToolCall.t() | nil
  def get_tool_call_by_openai_id(openai_call_id) when is_binary(openai_call_id) do
    Repo.get_by(ToolCall, openai_call_id: openai_call_id)
  end

  defp tap_broadcast_tool_call_changed({:ok, %ToolCall{} = tc} = result) do
    Phoenix.PubSub.broadcast(
      EllieAi.PubSub,
      "calls:lifecycle:#{tc.call_id}",
      {:call_changed, %{event: :tool_call_changed, call_id: tc.call_id, tool_call_id: tc.id}}
    )

    result
  end

  defp tap_broadcast_tool_call_changed(other), do: other

  # broadcast a lifecycle event on both topics so /customers (the homepage
  # ticker) and /calls/:id (the detail page) both update without one
  # subscribing to the other's events.
  defp broadcast_call_changed({:ok, %Call{} = call}) do
    payload = %{event: :status_changed, call_id: call.id, status: call.status}
    Phoenix.PubSub.broadcast(EllieAi.PubSub, "calls:lifecycle", {:call_changed, payload})

    Phoenix.PubSub.broadcast(
      EllieAi.PubSub,
      "calls:lifecycle:#{call.id}",
      {:call_changed, payload}
    )
  end

  defp broadcast_call_changed(_), do: :ok

  @doc """
  called by the Archivist at terminate. `key` may be nil if the upload
  failed or s3 isn't configured — the duration is still useful for ui.
  """
  @spec set_audio(Ecto.UUID.t(), String.t() | nil, non_neg_integer()) :: :ok
  def set_audio(call_id, key, duration_ms)
      when is_binary(call_id) and is_integer(duration_ms) and duration_ms >= 0 do
    case Repo.get(Call, call_id) do
      nil ->
        :ok

      %Call{} = call ->
        result =
          call
          |> Call.changeset(%{audio_s3_key: key, audio_duration_ms: duration_ms})
          |> Repo.update()

        broadcast_call_changed(result)
        :ok
    end
  end

  # ── system events ───────────────────────────────────────────────────────

  @doc """
  no-ops if the call row doesn't exist yet (very brief race during
  call.initiated handling). `source` is "telnyx" / "openai" / "vad" /
  "call_server" / "archivist"; `kind` is the dotted event name;
  `message` is a one-liner; `payload` carries the raw event.
  """
  @spec record_system_event(String.t(), String.t(), String.t(), String.t() | nil, map() | nil) ::
          :ok
  def record_system_event(ccid, source, kind, message \\ nil, payload \\ nil)
      when is_binary(ccid) and is_binary(source) and is_binary(kind) do
    case get_by_ccid(ccid) do
      nil ->
        :ok

      %Call{id: call_id} ->
        result =
          %SystemEvent{}
          |> SystemEvent.changeset(%{
            call_id: call_id,
            source: source,
            kind: kind,
            message: message,
            payload: payload
          })
          |> Repo.insert()

        case result do
          {:ok, _} ->
            Phoenix.PubSub.broadcast(
              EllieAi.PubSub,
              "calls:lifecycle:#{call_id}",
              {:call_changed, %{event: :system_event_recorded, call_id: call_id}}
            )

          _ ->
            :ok
        end

        :ok
    end
  end

  @spec list_system_events(Ecto.UUID.t()) :: [SystemEvent.t()]
  def list_system_events(call_id) when is_binary(call_id) do
    from(e in SystemEvent,
      where: e.call_id == ^call_id,
      order_by: [asc: e.inserted_at]
    )
    |> Repo.all()
  end

  @spec get_by_ccid(String.t()) :: Call.t() | nil
  def get_by_ccid(ccid) when is_binary(ccid), do: Repo.get_by(Call, provider_id: ccid)

  def list_recent(org_id, limit \\ 50) when is_binary(org_id) do
    from(c in Call,
      where: c.org_id == ^org_id,
      order_by: [desc: c.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "preloads turns in chronological order."
  def get(id) when is_binary(id) do
    case Repo.get(Call, id) do
      nil ->
        nil

      call ->
        Repo.preload(call,
          transcript_turns: from(t in TranscriptTurn, order_by: [asc: t.inserted_at])
        )
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
