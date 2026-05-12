defmodule EllieAiWeb.CustomerDetailLive do
  @moduledoc """
  per-customer conversation hub. layout:

    * sticky header — name, phone, email, last seen.
    * notes card  — inline editable.
    * two-pane body —
        left rail: every call this customer has had (jump-scroll target),
        main pane: unified conversation feed, grouped by date, with one
                   call divider per call (summary + audio + status).
    * sms composer at the bottom — attaches to the most recent call, so
      we have a parent for the transcript_turns row. cold-text without
      any prior call is deferred to a follow-up.

  live updates via the same `calls:lifecycle:<call_id>` pubsub channel
  used by the call detail page — we subscribe to ALL of the customer's
  call topics on mount.
  """

  use EllieAiWeb, :live_view

  alias EllieAi.{Calls, Customers}
  alias EllieAi.Calls.Constants
  alias EllieAi.Telnyx.Messaging

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = socket.assigns[:nav_org]

    case org && Customers.get(org.id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Customer not found")
         |> push_navigate(to: ~p"/")}

      customer ->
        calls = Calls.list_for_customer(customer.id)

        if connected?(socket) do
          for call <- calls do
            Phoenix.PubSub.subscribe(EllieAi.PubSub, "calls:lifecycle:#{call.id}")
          end
        end

        {:ok,
         socket
         |> assign(:page_title, display_name(customer))
         |> assign(:active_nav, :customers)
         |> assign(:org, org)
         |> assign(:customer, customer)
         |> assign(:calls, calls)
         |> assign(:editing_name, false)
         |> assign(:editing_notes, false)}
    end
  end

  @impl true
  def handle_info({:call_changed, _payload}, socket) do
    customer = Customers.get(socket.assigns.org.id, socket.assigns.customer.id)
    calls = Calls.list_for_customer(socket.assigns.customer.id)

    {:noreply,
     socket
     |> assign(:customer, customer || socket.assigns.customer)
     |> assign(:calls, calls)}
  end

  @impl true
  def handle_event("start_edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, true)}
  end

  def handle_event("cancel_edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, false)}
  end

  def handle_event("save_name", %{"customer_id" => id, "name" => raw}, socket) do
    {first, last} = Customers.split_name(raw)

    case Customers.update_by_id(socket.assigns.org.id, id, %{first_name: first, last_name: last}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:customer, updated)
         |> assign(:editing_name, false)
         |> put_flash(:info, "Name saved")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:editing_name, false)
         |> put_flash(:error, "Couldn't save: #{inspect(reason)}")}
    end
  end

  def handle_event("start-edit-notes", _params, socket) do
    {:noreply, assign(socket, :editing_notes, true)}
  end

  def handle_event("cancel-edit-notes", _params, socket) do
    {:noreply, assign(socket, :editing_notes, false)}
  end

  def handle_event("save-notes", %{"notes" => notes}, socket) do
    case Customers.update_by_id(socket.assigns.org.id, socket.assigns.customer.id, %{notes: notes}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:customer, updated)
         |> assign(:editing_notes, false)
         |> put_flash(:info, "Notes saved")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:editing_notes, false)
         |> put_flash(:error, "Couldn't save notes: #{inspect(reason)}")}
    end
  end

  def handle_event("send-sms", %{"text" => raw}, socket) do
    text = raw |> to_string() |> String.trim()
    customer = socket.assigns.customer
    org = socket.assigns.org
    last_call = List.first(socket.assigns.calls)

    cond do
      text == "" ->
        {:noreply, put_flash(socket, :error, "Type a message first")}

      is_nil(customer.phone_e164) ->
        {:noreply, put_flash(socket, :error, "No phone number on file for this customer")}

      is_nil(last_call) ->
        {:noreply,
         put_flash(socket, :error, "SMS cold-text without a prior call isn't supported yet")}

      true ->
        case Messaging.send_sms(org, customer.phone_e164, text) do
          {:ok, _telnyx_id} ->
            _ = Calls.append_sms_turn(last_call.provider_id, Constants.role_staff(), text)

            {:noreply,
             socket
             |> assign(:calls, Calls.list_for_customer(customer.id))
             |> put_flash(:info, "SMS sent")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "SMS failed: #{inspect(reason)}")}
        end
    end
  end

  # ── timeline construction ──────────────────────────────────────────────

  # build a flat list of {date, [day_items]} where each day_item is one
  # of: {:call_divider, call} | {:turn, turn, call_id}. days are sorted
  # ascending so the feed reads chronologically. within a day items are
  # sorted by their event time (call.started_at for the divider, then
  # the call's turns by their inserted_at).
  defp build_feed(calls) do
    # each call contributes a divider event AT call.started_at, then its
    # turns AFTER the divider. we flatten everything to {date, time, item}
    # tuples, sort, then group.
    events =
      calls
      |> Enum.reverse()
      |> Enum.flat_map(fn call ->
        divider = {call.started_at || call.inserted_at, {:call_divider, call}}

        turn_events =
          (call.transcript_turns || [])
          |> Enum.map(fn t ->
            ts = t.started_at || t.inserted_at
            {ts, {:turn, t, call.id}}
          end)

        [divider | turn_events]
      end)
      |> Enum.sort_by(fn {ts, _} -> ts end, DateTime)
      |> Enum.map(fn {ts, item} -> {DateTime.to_date(ts), item} end)

    events
    |> Enum.chunk_by(fn {date, _} -> date end)
    |> Enum.map(fn day_chunk ->
      date = day_chunk |> hd() |> elem(0)
      items = Enum.map(day_chunk, fn {_d, item} -> item end)
      {date, items}
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :feed, build_feed(assigns.calls))

    ~H"""
    <div class="space-y-4">
      <div>
        <.link navigate={~p"/"} class="text-xs text-muted-foreground hover:text-foreground">
          ← Back to customers
        </.link>
      </div>

      <.panel elevated>
        <div class="flex items-center gap-3 flex-wrap">
          <.editable_name customer={@customer} editing?={@editing_name} size="lg" />
          <.phone phone={@customer.phone_e164} />
        </div>
        <div class="mono text-xs text-muted-foreground mt-2 flex flex-wrap items-center gap-x-2 gap-y-1">
          <span :if={@customer.email}>{@customer.email}</span>
          <span :if={@customer.email}>·</span>
          <span :if={@customer.first_seen_at}>
            first seen <.datetime at={@customer.first_seen_at} />
          </span>
          <span :if={@customer.first_seen_at && @customer.last_seen_at}>·</span>
          <span :if={@customer.last_seen_at}>
            last seen <.datetime at={@customer.last_seen_at} />
          </span>
        </div>
      </.panel>

      <section class="rounded-lg border border-border bg-card shadow-[var(--shadow-sm)]">
        <header class="px-6 pt-5 pb-3 flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold text-foreground flex items-center gap-2">
            <.icon name="hero-document-text" class="h-4 w-4 text-muted-foreground" />
            Notes
          </h2>
          <button
            :if={!@editing_notes}
            type="button"
            phx-click="start-edit-notes"
            class="text-xs text-primary font-medium hover:text-primary-hover transition-colors duration-[var(--motion-fast)]"
          >
            Edit
          </button>
        </header>

        <div class="px-6 pb-6">
          <div :if={!@editing_notes}>
            <div :if={@customer.notes} class="text-sm text-foreground whitespace-pre-line leading-relaxed">
              {@customer.notes}
            </div>
            <button
              :if={!@customer.notes}
              type="button"
              phx-click="start-edit-notes"
              class="text-sm text-muted-foreground italic hover:text-foreground transition-colors duration-[var(--motion-fast)] text-left"
            >
              + add notes for {display_name(@customer)}
            </button>
          </div>

          <form
            :if={@editing_notes}
            phx-submit="save-notes"
            phx-window-keydown="cancel-edit-notes"
            phx-key="Escape"
            class="space-y-3"
          >
            <textarea
              name="notes"
              rows="4"
              autofocus
              placeholder="VIP, allergies, dietary preferences, anything staff should know on the next call…"
              class="w-full text-sm rounded-md border border-ring bg-background px-3 py-2 text-foreground leading-relaxed resize-y focus:outline-none focus:ring-2 focus:ring-ring"
            ><%= @customer.notes %></textarea>
            <div class="flex justify-end gap-2">
              <button
                type="button"
                phx-click="cancel-edit-notes"
                class="text-xs px-3 py-1.5 rounded-md border border-border bg-secondary text-foreground hover:bg-accent transition-colors duration-[var(--motion-fast)]"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="text-xs px-3 py-1.5 rounded-md bg-primary text-primary-foreground font-semibold hover:bg-primary-hover transition-colors duration-[var(--motion-fast)]"
              >
                Save
              </button>
            </div>
          </form>
        </div>
      </section>

      <div class="grid grid-cols-1 lg:grid-cols-[1fr_3fr] gap-4">
        <aside class="rounded-md border border-border bg-card p-4 h-fit max-h-[70vh] overflow-y-auto">
          <h2 class="text-sm font-semibold text-foreground mb-3">
            Calls <span class="mono text-xs text-muted-foreground">{length(@calls)}</span>
          </h2>

          <p :if={@calls == []} class="text-sm text-muted-foreground italic">
            No calls yet.
          </p>

          <ul class="space-y-1">
            <li :for={call <- @calls}>
              <a
                href={"#call-#{call.id}"}
                class="block px-2 py-2 rounded hover:bg-secondary/60 transition-colors duration-[var(--motion-fast)]"
              >
                <div class="flex items-center gap-2 flex-wrap">
                  <.status_pill status={call.status} />
                  <.datetime at={call.started_at} format={:short} />
                </div>
                <div :if={call.summary} class="text-xs text-foreground mt-1 line-clamp-2">
                  {call.summary}
                </div>
                <div :if={!call.summary} class="text-xs text-muted-foreground italic mt-1">
                  (no summary yet)
                </div>
              </a>
            </li>
          </ul>
        </aside>

        <div
          id="conversation-feed"
          class="rounded-md border border-border bg-card p-4 max-h-[70vh] overflow-y-auto"
        >
          <div :if={@feed == []} class="text-center text-sm text-muted-foreground italic py-12">
            No conversation yet. Calls and SMS show up here as they happen.
          </div>

          <div :for={{date, items} <- @feed} class="mb-4">
            <.date_divider date={date} />

            <div :for={item <- items}>
              <.feed_item item={item} call_id={call_id_for(item)} />
            </div>
          </div>
        </div>
      </div>

      <section class="rounded-lg border border-border bg-card shadow-[var(--shadow-sm)]">
        <header class="px-6 pt-5 pb-3 flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold text-foreground flex items-center gap-2">
            <.icon name="hero-chat-bubble-bottom-center-text" class="h-4 w-4 text-muted-foreground" />
            Send SMS
          </h2>
          <span :if={@customer.phone_e164} class="mono text-[11px] text-muted-foreground">
            to <.phone phone={@customer.phone_e164} />
          </span>
        </header>

        <form phx-submit="send-sms" class="px-6 pb-6 space-y-3">
          <textarea
            name="text"
            rows="3"
            placeholder="Type a message to send…"
            class="w-full text-sm rounded-md border border-border bg-background px-3 py-2 text-foreground leading-relaxed resize-none focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring transition-colors duration-[var(--motion-fast)]"
            required
          ></textarea>
          <div class="flex items-center justify-between gap-3">
            <span class="text-[11px] text-muted-foreground">
              <%= if @calls == [] do %>
                A prior call is needed before texting (cold-text shipping soon).
              <% else %>
                Attaches to the most recent call.
              <% end %>
            </span>
            <button
              type="submit"
              class="text-xs px-4 py-1.5 rounded-md bg-primary text-primary-foreground font-semibold hover:bg-primary-hover transition-colors duration-[var(--motion-fast)] inline-flex items-center gap-1.5"
            >
              Send
              <.icon name="hero-paper-airplane" class="h-3.5 w-3.5" />
            </button>
          </div>
        </form>
      </section>
    </div>
    """
  end

  # ── components ─────────────────────────────────────────────────────────

  attr :date, :any, required: true

  defp date_divider(assigns) do
    ~H"""
    <div class="flex items-center gap-3 my-4">
      <div class="flex-1 h-px bg-border"></div>
      <div class="mono text-[11px] uppercase tracking-wider text-muted-foreground">
        {format_day(@date)}
      </div>
      <div class="flex-1 h-px bg-border"></div>
    </div>
    """
  end

  attr :item, :any, required: true
  attr :call_id, :any, default: nil

  defp feed_item(%{item: {:call_divider, call}} = assigns) do
    assigns = assign(assigns, :call, call)

    ~H"""
    <div id={"call-#{@call.id}"} class="my-4 rounded-md border border-border bg-background/40 p-4 space-y-3">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div class="flex items-center gap-2 flex-wrap">
          <.status_pill status={@call.status} />
          <span class="mono text-xs text-muted-foreground">
            <.datetime at={@call.started_at} format={:time} />
          </span>
          <span :if={@call.ended_at} class="mono text-[11px] text-muted-foreground">
            · {call_duration(@call)}
          </span>
          <span :if={@call.hangup_reason} class="mono text-[10px] uppercase tracking-wider text-muted-foreground">
            · {@call.hangup_reason}
          </span>
        </div>
        <.link
          navigate={~p"/calls/#{@call.id}"}
          class="text-xs text-primary font-medium hover:text-primary-hover"
        >
          open call →
        </.link>
      </div>

      <div :if={@call.summary} class="text-sm text-foreground italic">
        {@call.summary}
      </div>

      <div :if={@call.audio_duration_ms} class="space-y-1">
        <div class="mono text-[10px] uppercase tracking-wide text-muted-foreground">
          recording · {format_duration_ms(@call.audio_duration_ms)}
        </div>
        <audio
          controls
          preload="none"
          src={~p"/calls/#{@call.id}/audio?token=#{audio_token(@call.id)}"}
          class="w-full"
        >
          Your browser does not support audio playback.
        </audio>
      </div>
    </div>
    """
  end

  defp feed_item(%{item: {:turn, turn, _cid}} = assigns) do
    assigns = assign(assigns, :turn, turn)

    ~H"""
    <div class={turn_class(@turn.role, @turn.medium)}>
      <div class="mono text-[11px] text-muted-foreground mb-1 flex items-center gap-2">
        <span>{@turn.role}</span>
        <span :if={@turn.medium == "sms"} class="mono text-[9px] uppercase tracking-wider px-1 py-0.5 rounded bg-foreground/10 text-foreground/80">sms</span>
        <span aria-hidden="true">·</span>
        <.datetime at={@turn.started_at || @turn.inserted_at} format={:time} />
      </div>
      <div class="text-sm text-foreground whitespace-pre-line">{@turn.text}</div>
    </div>
    """
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp call_id_for({:call_divider, %{id: id}}), do: id
  defp call_id_for({:turn, _, cid}), do: cid

  # voice turns: paragraph blocks; sms turns: chat bubbles.
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

  defp call_duration(%{started_at: nil}), do: "—"
  defp call_duration(%{ended_at: nil}), do: "—"

  defp call_duration(%{started_at: s, ended_at: e}) do
    secs = DateTime.diff(e, s, :second)
    "#{div(secs, 60)}m #{rem(secs, 60)}s"
  end

  defp format_duration_ms(ms) when is_integer(ms) and ms >= 0 do
    secs = div(ms, 1000)
    "#{div(secs, 60)}m #{rem(secs, 60)}s"
  end

  defp format_duration_ms(_), do: "—"

  defp audio_token(call_id) do
    Phoenix.Token.sign(EllieAiWeb.Endpoint, "call audio", call_id)
  end

  defp format_day(%Date{} = date) do
    today = Date.utc_today()

    cond do
      date == today -> "Today"
      date == Date.add(today, -1) -> "Yesterday"
      true -> Calendar.strftime(date, "%A · %b %-d, %Y")
    end
  end
end
