defmodule EllieAiWeb.CallDetailLive do
  @moduledoc """
  per-call detail page. one merged timeline (turns + tool calls, plus
  system events when "Show logs" is on) on the left; customer card +
  SMS composer placeholder on the right rail.

  audio player sits in the header when archival finished. live updates
  via the `calls:lifecycle:<id>` pubsub topic.
  """

  use EllieAiWeb, :live_view

  alias EllieAi.{Calls, Customers, Orgs, RestoClient}
  alias EllieAi.Calls.Constants
  alias EllieAi.Telnyx.Messaging
  alias EllieAi.Tools.Catalog

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Calls.get(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Call not found")
         |> push_navigate(to: ~p"/")}

      call ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(EllieAi.PubSub, "calls:lifecycle:#{id}")
        end

        org = Orgs.get(call.org_id)
        {customer, reservations} = load_customer_context(org, call.from_phone)

        {:ok,
         socket
         |> assign(:page_title, "Call #{short_id(id)}")
         |> assign(:active_nav, :calls)
         |> assign(:call, call)
         |> assign(:customer, customer)
         |> assign(:reservations, reservations)
         |> assign(:tool_calls, Calls.list_tool_calls(id))
         |> assign(:system_events, Calls.list_system_events(id))
         |> assign(:show_logs, false)
         |> assign(:expanded_tool_call_id, nil)
         |> assign(:confirm_replay_id, nil)}
    end
  end

  @impl true
  def handle_info({:call_changed, _payload}, socket) do
    case Calls.get(socket.assigns.call.id) do
      nil ->
        {:noreply, socket}

      call ->
        # only refetch the customer rail if the from_phone has shifted
        # (it almost never does — but for transferred calls it can).
        {customer, reservations} =
          if call.from_phone == socket.assigns.call.from_phone do
            {socket.assigns.customer, socket.assigns.reservations}
          else
            org = Orgs.get(call.org_id)
            load_customer_context(org, call.from_phone)
          end

        {:noreply,
         socket
         |> assign(:call, call)
         |> assign(:customer, customer)
         |> assign(:reservations, reservations)
         |> assign(:tool_calls, Calls.list_tool_calls(call.id))
         |> assign(:system_events, Calls.list_system_events(call.id))}
    end
  end

  @impl true
  def handle_event("toggle-tool-call", %{"id" => id}, socket) do
    current = socket.assigns.expanded_tool_call_id
    next = if current == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_tool_call_id, next)}
  end

  def handle_event("toggle-logs", _params, socket) do
    {:noreply, assign(socket, :show_logs, not socket.assigns.show_logs)}
  end

  def handle_event("request-replay", %{"id" => id, "write" => "true"}, socket) do
    # write tools open the confirm modal first per design review 7B.
    {:noreply, assign(socket, :confirm_replay_id, id)}
  end

  def handle_event("request-replay", %{"id" => id}, socket) do
    # read tools fire immediately, no confirmation.
    do_replay(socket, id)
  end

  def handle_event("cancel-replay", _params, socket) do
    {:noreply, assign(socket, :confirm_replay_id, nil)}
  end

  def handle_event("confirm-replay", %{"id" => id}, socket) do
    do_replay(socket, id)
  end

  # staff composer: send an sms to the caller from the org's telnyx
  # number. on success we append a `staff` / `sms` turn so the timeline
  # reflects the outbound message immediately; the delivery receipt
  # webhook lands separately and is currently ignored.
  def handle_event("send-sms", %{"text" => raw}, socket) do
    text = raw |> to_string() |> String.trim()
    call = socket.assigns.call
    org = Orgs.get(call.org_id)

    cond do
      text == "" ->
        {:noreply, put_flash(socket, :error, "Type a message first")}

      is_nil(org) ->
        {:noreply, put_flash(socket, :error, "No org for this call")}

      is_nil(call.from_phone) ->
        {:noreply, put_flash(socket, :error, "No caller number on this call")}

      true ->
        case Messaging.send_sms(org, call.from_phone, text) do
          {:ok, _telnyx_id} ->
            _ = Calls.append_sms_turn(call.provider_id, Constants.role_staff(), text)
            refreshed = Calls.get(call.id)

            {:noreply,
             socket
             |> assign(:call, refreshed)
             |> put_flash(:info, "SMS sent")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "SMS failed: #{inspect(reason)}")}
        end
    end
  end

  defp do_replay(socket, tool_call_id) do
    case Calls.replay_tool_call(tool_call_id, nil) do
      {:ok, _new_row} ->
        {:noreply,
         socket
         |> assign(:tool_calls, Calls.list_tool_calls(socket.assigns.call.id))
         |> assign(:confirm_replay_id, nil)
         |> put_flash(:info, "Tool replayed")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:confirm_replay_id, nil)
         |> put_flash(:error, "Replay failed: #{inspect(reason)}")}
    end
  end

  # right rail context: cache hit is enough — we don't want a synchronous
  # resto round-trip blocking page render. nightly reconciliation keeps
  # the cache fresh; if a brand-new caller hasn't been mirrored yet we
  # just render the empty state.
  defp load_customer_context(nil, _phone), do: {nil, []}
  defp load_customer_context(_org, nil), do: {nil, []}

  defp load_customer_context(org, phone) do
    case Customers.lookup_by_phone(org, phone) do
      {:ok, %{id: id} = customer} ->
        reservations =
          case RestoClient.list_customer_reservations(org, id) do
            {:ok, list} -> list
            _ -> []
          end

        {customer, reservations}

      _ ->
        {nil, []}
    end
  end

  # merge turns + tool calls (always) + system events (opt-in) into a
  # single chronological list. each item is `{kind, row, timestamp}`.
  defp timeline(turns, tool_calls, system_events, show_logs?) do
    turn_items = Enum.map(turns, fn t -> {:turn, t, turn_at(t)} end)
    tool_items = Enum.map(tool_calls, fn tc -> {:tool_call, tc, tc.inserted_at} end)

    event_items =
      if show_logs?,
        do: Enum.map(system_events, fn ev -> {:system_event, ev, ev.inserted_at} end),
        else: []

    Enum.sort_by(turn_items ++ tool_items ++ event_items, fn {_k, _r, ts} -> ts end, DateTime)
  end

  defp turn_at(%{started_at: %DateTime{} = t}), do: t
  defp turn_at(%{inserted_at: t}), do: t

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <.link navigate={~p"/calls"} class="text-xs text-muted-foreground hover:text-foreground">
          ← Back to calls
        </.link>
      </div>

      <section class="rounded-md border border-border bg-card p-5">
        <h1 class="flex items-center gap-3 flex-wrap text-xl font-semibold tracking-tight text-foreground">
          Call {short_id(@call.id)}
          <.status_pill status={@call.status} />
        </h1>
        <div class="mono text-xs text-muted-foreground mt-2 flex flex-wrap items-center gap-x-2 gap-y-1">
          <.phone phone={@call.from_phone} />
          <span aria-hidden="true">→</span>
          <.phone phone={@call.to_phone} />
          <span>·</span>
          <span>started <.datetime at={@call.started_at} /></span>
          <span :if={@call.ended_at}>·</span>
          <span :if={@call.ended_at}>ended <.datetime at={@call.ended_at} /></span>
          <span :if={@call.ended_at}>·</span>
          <span :if={@call.ended_at}>duration {duration(@call)}</span>
          <span :if={@call.hangup_reason}>·</span>
          <span :if={@call.hangup_reason}>reason {@call.hangup_reason}</span>
        </div>

        <div :if={@call.audio_duration_ms} class="mt-4">
          <div class="mono text-[11px] text-muted-foreground mb-1">
            recording · {format_duration_ms(@call.audio_duration_ms)}
          </div>
          <audio
            controls
            preload="metadata"
            src={~p"/calls/#{@call.id}/audio?token=#{audio_token(@call.id)}"}
            class="w-full"
          >
            Your browser does not support audio playback.
          </audio>
        </div>
      </section>

      <div class="grid grid-cols-1 lg:grid-cols-[3fr_2fr] gap-4">
        <div
          id="transcript-pane"
          phx-hook="ScrollAnchor"
          class="rounded-md border border-border bg-card p-4 max-h-[70vh] overflow-y-auto"
        >
          <div class="flex items-center justify-between mb-3 pb-2 border-b border-border">
            <button
              type="button"
              phx-click="toggle-logs"
              class="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1.5"
              aria-pressed={if @show_logs, do: "true", else: "false"}
            >
              <span aria-hidden="true">{if @show_logs, do: "▾", else: "▸"}</span>
              {if @show_logs, do: "Hide logs", else: "Show logs"}
              <span class="mono text-[10px] text-muted-foreground">({length(@system_events)})</span>
            </button>
          </div>

          <div
            :if={timeline(@call.transcript_turns, @tool_calls, @system_events, @show_logs) == []}
            class="text-center text-sm text-muted-foreground italic py-12"
          >
            <span class="inline-block h-2 w-2 rounded-full bg-primary mr-2 animate-pulse" aria-hidden="true"></span>
            Waiting for the conversation to begin…
          </div>

          <div :for={item <- timeline(@call.transcript_turns, @tool_calls, @system_events, @show_logs)}>
            <.timeline_row
              item={item}
              expanded_tool_call_id={@expanded_tool_call_id}
            />
          </div>
        </div>

        <aside class="space-y-4 h-fit">
          <div class="rounded-md border border-border bg-card p-5">
            <h2 class="text-sm font-semibold text-foreground mb-3">Customer</h2>

            <div :if={@customer}>
              <div class="text-base font-semibold text-foreground">
                {customer_label(@customer)}
              </div>
              <div class="mono text-xs text-muted-foreground mt-1">
                <.phone phone={@customer.phone_e164} />
              </div>
              <div :if={@customer.email} class="text-xs text-muted-foreground mt-1">
                {@customer.email}
              </div>
              <div :if={@customer.first_seen_at} class="mono text-[11px] text-muted-foreground mt-2">
                first seen <.datetime at={@customer.first_seen_at} />
              </div>
              <div :if={@customer.notes} class="text-sm text-foreground mt-3 whitespace-pre-line border-l-2 border-border pl-3">
                {@customer.notes}
              </div>
            </div>

            <div :if={!@customer} class="text-sm text-muted-foreground italic">
              No matching customer for <.phone phone={@call.from_phone} /> yet. The reconciliation cron may not have synced.
            </div>
          </div>

          <div :if={@reservations != []} class="rounded-md border border-border bg-card p-5">
            <h2 class="text-sm font-semibold text-foreground mb-3">Recent reservations</h2>
            <ul class="space-y-2">
              <li :for={r <- Enum.take(@reservations, 8)} class="text-sm text-foreground border-b border-border/40 last:border-0 pb-2 last:pb-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="mono text-[12px] text-foreground">{reservation_when(r)}</span>
                  <span class="mono text-[11px] text-muted-foreground">party {reservation_field(r, "party_size") || "—"}</span>
                </div>
                <div :if={reservation_field(r, "status")} class="mono text-[10px] uppercase tracking-wide text-muted-foreground mt-0.5">
                  {reservation_field(r, "status")}
                </div>
              </li>
            </ul>
          </div>

          <div class="rounded-md border border-border bg-card p-5">
            <h2 class="text-sm font-semibold text-foreground mb-3">Send SMS</h2>
            <form phx-submit="send-sms" class="space-y-2">
              <textarea
                name="text"
                rows="3"
                placeholder={"Text " <> (@call.from_phone || "caller") <> "…"}
                class="w-full text-sm rounded border border-border bg-background px-2 py-1.5 text-foreground resize-none focus:outline-none focus:ring-2 focus:ring-ring"
                required
              ></textarea>
              <div class="flex justify-end">
                <button
                  type="submit"
                  class="text-xs px-3 py-1 rounded bg-primary text-primary-foreground font-semibold hover:bg-primary-hover transition-colors duration-[var(--motion-fast)]"
                >
                  Send
                </button>
              </div>
            </form>
          </div>
        </aside>
      </div>

      <div
        :if={@confirm_replay_id}
        class="fixed inset-0 bg-background/80 flex items-center justify-center p-4 z-50"
        phx-window-keydown="cancel-replay"
        phx-key="escape"
      >
        <div class="rounded-md border border-border bg-card p-5 max-w-sm space-y-3">
          <h3 class="text-base font-semibold text-foreground">Replay write tool?</h3>
          <p class="text-sm text-foreground">
            This tool mutates resto (creates, modifies, or cancels a reservation).
            The original row stays untouched; a new row will record this replay.
          </p>
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel-replay"
              class="text-xs px-3 py-1 rounded border border-border bg-secondary text-foreground"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="confirm-replay"
              phx-value-id={@confirm_replay_id}
              class="text-xs px-3 py-1 rounded bg-primary text-primary-foreground font-semibold"
            >
              Replay
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── timeline rows ──────────────────────────────────────────────────────

  attr :item, :any, required: true
  attr :expanded_tool_call_id, :string, default: nil

  defp timeline_row(%{item: {:turn, turn, _ts}} = assigns) do
    assigns = assign(assigns, :turn, turn)

    ~H"""
    <div class={turn_class(@turn.role, @turn.medium)}>
      <div class="mono text-[11px] text-muted-foreground mb-1 flex items-center gap-2">
        <span>{@turn.role}</span>
        <span :if={@turn.medium == "sms"} class="mono text-[9px] uppercase tracking-wider px-1 py-0.5 rounded bg-foreground/10 text-foreground/80">sms</span>
        <span aria-hidden="true">·</span>
        <.datetime at={@turn.started_at || @turn.inserted_at} format={:time} />
        <span
          :if={@turn.sentiment_score}
          class={sentiment_chip_class(@turn.sentiment_score)}
          title={"sentiment #{Float.round(@turn.sentiment_score, 2)}"}
        >
          {Float.round(@turn.sentiment_score, 2)}
        </span>
      </div>
      <div class="text-sm text-foreground whitespace-pre-line">{@turn.text}</div>
    </div>
    """
  end

  defp timeline_row(%{item: {:tool_call, tc, _ts}} = assigns) do
    assigns =
      assigns
      |> assign(:tc, tc)
      |> assign(:expanded?, assigns.expanded_tool_call_id == tc.id)
      |> assign(:write?, Catalog.write?(tc.tool_name))

    ~H"""
    <div class={["mb-2", tool_row_class(@tc.status)]}>
      <button
        type="button"
        phx-click="toggle-tool-call"
        phx-value-id={@tc.id}
        class="w-full text-left flex items-center justify-between gap-2 px-3 py-2"
      >
        <span class="flex items-center gap-2 min-w-0">
          <span class={dot_class(@tc.status)} aria-hidden="true"></span>
          <span class="mono text-[13px] text-foreground truncate">{@tc.tool_name}</span>
          <span :if={@tc.replayed_from_id} class="text-[10px] uppercase tracking-wide text-muted-foreground">replay</span>
        </span>
        <span class="mono text-[11px] text-muted-foreground shrink-0">
          <%= @tc.duration_ms %>ms
        </span>
      </button>

      <div :if={@expanded?} class="px-3 pb-3 space-y-2">
        <div>
          <div class="mono text-[10px] uppercase tracking-wide text-muted-foreground">arguments</div>
          <pre class="mono text-[11px] text-foreground bg-background rounded p-2 overflow-x-auto">{format_json(@tc.arguments)}</pre>
        </div>

        <div :if={@tc.result}>
          <div class="mono text-[10px] uppercase tracking-wide text-muted-foreground">result</div>
          <pre class="mono text-[11px] text-foreground bg-background rounded p-2 overflow-x-auto">{format_json(@tc.result)}</pre>
        </div>

        <div :if={@tc.error}>
          <div class="mono text-[10px] uppercase tracking-wide text-destructive">error</div>
          <pre class="mono text-[11px] text-destructive bg-background rounded p-2 overflow-x-auto whitespace-pre-wrap">{@tc.error}</pre>
        </div>

        <button
          type="button"
          phx-click="request-replay"
          phx-value-id={@tc.id}
          phx-value-write={if @write?, do: "true", else: "false"}
          class="text-xs px-2 py-1 rounded border border-border bg-secondary hover:bg-accent text-foreground"
        >
          Replay
        </button>
      </div>
    </div>
    """
  end

  defp timeline_row(%{item: {:system_event, ev, _ts}} = assigns) do
    assigns = assign(assigns, :ev, ev)

    ~H"""
    <div class="mb-2 rounded border border-border/40 bg-background/40 px-3 py-1.5">
      <div class="mono text-[11px] text-muted-foreground flex items-center gap-2 flex-wrap">
        <span class="inline-block h-1.5 w-1.5 rounded-full bg-muted-foreground/60" aria-hidden="true"></span>
        <span>{@ev.source}</span>
        <span aria-hidden="true">·</span>
        <span class="text-foreground">{@ev.kind}</span>
        <span aria-hidden="true">·</span>
        <.datetime at={@ev.inserted_at} format={:time} />
      </div>
      <div :if={@ev.message} class="text-[12px] text-foreground mt-0.5">{@ev.message}</div>
    </div>
    """
  end

  # ── helpers ────────────────────────────────────────────────────────────

  # voice turns: paragraph blocks (paper bg for assistant, accent bg for user).
  # sms turns: chat bubble shape, ring outline, narrower so they read as
  # "side channel" relative to the voice transcript.
  defp turn_class("user", "voice"),
    do: "rounded-md bg-accent p-3 mb-2 mr-6"

  defp turn_class("assistant", "voice"),
    do: "rounded-md bg-secondary p-3 mb-2 ml-6"

  defp turn_class("user", "sms"),
    do: "rounded-2xl border border-border bg-accent/60 p-3 mb-2 mr-12 max-w-[80%]"

  defp turn_class("staff", "sms"),
    do: "rounded-2xl border border-primary/30 bg-primary/10 p-3 mb-2 ml-12 max-w-[80%] ml-auto"

  defp turn_class(_, _),
    do: "rounded-md bg-secondary p-3 mb-2"

  defp short_id(<<prefix::binary-size(8), _rest::binary>>), do: prefix
  defp short_id(other), do: other

  defp duration(%{started_at: nil}), do: "—"
  defp duration(%{ended_at: nil}), do: "—"

  defp duration(%{started_at: s, ended_at: e}) do
    secs = DateTime.diff(e, s, :second)
    "#{div(secs, 60)}m #{rem(secs, 60)}s"
  end

  defp format_duration_ms(ms) when is_integer(ms) and ms >= 0 do
    secs = div(ms, 1000)
    "#{div(secs, 60)}m #{rem(secs, 60)}s"
  end

  defp format_duration_ms(_), do: "—"

  # sign a short-lived token so the audio URL itself acts as the cred.
  # the surrounding staff page is unauthenticated, but the audio file
  # is PII (caller's voice) — gating the wav behind a verifier means a
  # link leaked from logs/history doesn't expose recordings indefinitely.
  defp audio_token(call_id) do
    Phoenix.Token.sign(EllieAiWeb.Endpoint, "call audio", call_id)
  end

  defp tool_row_class("ok"), do: "rounded border border-border bg-secondary/60"
  defp tool_row_class("error"), do: "rounded border border-destructive/40 bg-destructive/10"
  defp tool_row_class(_), do: "rounded border border-border bg-card"

  defp dot_class("ok"), do: "inline-block h-2 w-2 rounded-full bg-primary"
  defp dot_class("error"), do: "inline-block h-2 w-2 rounded-full bg-destructive"
  defp dot_class(_), do: "inline-block h-2 w-2 rounded-full bg-primary animate-pulse"

  defp format_json(nil), do: "—"

  defp format_json(map) when is_map(map) do
    Jason.encode!(map, pretty: true)
  rescue
    _ -> inspect(map)
  end

  defp format_json(other), do: inspect(other)

  # sage / warm-grey / red palette per design review pass 5C — independent
  # of the teal accent so the chips read as "feeling", not "status".
  defp sentiment_chip_class(score) when is_float(score) do
    cond do
      score >= 0.6 -> "mono text-[10px] px-1.5 py-0.5 rounded bg-green-100 text-green-900"
      score >= 0.3 -> "mono text-[10px] px-1.5 py-0.5 rounded bg-amber-100 text-amber-900"
      true -> "mono text-[10px] px-1.5 py-0.5 rounded bg-red-100 text-red-900"
    end
  end

  defp sentiment_chip_class(_), do: "hidden"

  defp customer_label(%{} = c) do
    [c.salutation, c.first_name, c.last_name]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" -> "(no name on file)"
      name -> name
    end
  end

  # resto returns reservations as plain maps from JSON, so field access
  # is string-keyed. fall back through likely shapes so a schema tweak
  # on the resto side doesn't blank the rail.
  defp reservation_field(r, key) when is_map(r), do: r[key] || r[String.to_atom(key)]
  defp reservation_field(_, _), do: nil

  defp reservation_when(r) do
    date = reservation_field(r, "date") || reservation_field(r, "reserved_date")
    time = reservation_field(r, "time") || reservation_field(r, "reserved_time")

    case {date, time} do
      {nil, nil} -> "—"
      {d, nil} -> to_string(d)
      {nil, t} -> to_string(t)
      {d, t} -> "#{d} · #{t}"
    end
  end
end
