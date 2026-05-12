defmodule EllieAiWeb.CallsLive do
  @moduledoc """
  recent calls index. dense table inspired by the Vapi / Retell / Bland
  dashboards: one row per call, status pill, duration, customer link,
  sentiment glyph. live: subscribes to `calls:lifecycle` so new rings
  appear at the top in real time.

  for the smoke-test corpus we just show the most recent 100. when call
  volume grows past v0 we'll add filters (status, date range) and
  pagination — kept out of the first cut to land the layout fast.
  """

  use EllieAiWeb, :live_view

  alias EllieAi.{Calls, Customers}
  alias EllieAi.Calls.Constants

  @pubsub_topic "calls:lifecycle"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(EllieAi.PubSub, @pubsub_topic)

    {:ok,
     socket
     |> assign(:page_title, "Calls")
     |> assign(:active_nav, :calls)
     |> load_calls()}
  end

  @impl true
  def handle_info({:call_changed, _payload}, socket) do
    {:noreply, load_calls(socket)}
  end

  @impl true
  def handle_event("end_call", %{"ccid" => ccid}, socket) when is_binary(ccid) do
    # staff-driven hangup. drops the telnyx leg, marks our row ended,
    # tears down the supervision tree. broadcast comes from inside
    # finish_call → broadcast_call_changed, so the row flips status
    # without an extra round-trip.
    Calls.end_call(ccid)

    {:noreply,
     socket
     |> put_flash(:info, "Call ended.")
     |> load_calls()}
  end

  defp load_calls(socket) do
    org = socket.assigns[:nav_org]

    calls =
      case org do
        nil -> []
        _ -> Calls.list_recent(org.id, 100)
      end

    # build a phone → customer map in one query rather than n lookups.
    customers_by_phone =
      case org do
        nil ->
          %{}

        _ ->
          org.id
          |> Customers.list(limit: 500)
          |> Map.new(&{&1.phone_e164, &1})
      end

    socket
    |> assign(:calls, calls)
    |> assign(:customers_by_phone, customers_by_phone)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.page_header title="Calls">
        <:subtitle>
          Most recent {length(@calls)} calls{org_suffix(@nav_org)}.
        </:subtitle>
      </.page_header>

      <.empty_state
        :if={@calls == []}
        icon="hero-phone"
        title="No calls yet"
      >
        <:description>
          Calls will appear here as soon as someone dials Ellie's number.
        </:description>
      </.empty_state>

      <.panel :if={@calls != []} elevated>
        <table class="w-full text-sm">
          <thead class="bg-secondary text-muted-foreground border-b border-border">
            <tr class="text-left">
              <th class="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider">When</th>
              <th class="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider">Customer</th>
              <th class="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider">From</th>
              <th class="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider">Status</th>
              <th class="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider">Duration</th>
              <th class="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider">Sentiment</th>
              <th class="px-4 py-2.5 text-right"></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={call <- @calls}
              class={"relative cursor-pointer border-t border-border hover:bg-secondary/40 transition-colors duration-[var(--motion-fast)] " <> live_row_class(call)}
            >
              <%!-- whole-row click target. nested links/buttons below opt out via `relative z-10`. --%>
              <td class="px-4 py-2.5 align-middle">
                <.link
                  navigate={~p"/calls/#{call.id}"}
                  class="absolute inset-0 z-0"
                  aria-label={"Open call from " <> (call.from_phone || "unknown")}
                ><span class="sr-only">Open call detail</span></.link>
                <span class="relative"><.datetime at={call.started_at} format={:short} /></span>
              </td>
              <td class="px-4 py-2.5 align-middle">
                <%= case @customers_by_phone[call.from_phone] do %>
                  <% nil -> %>
                    <span class="text-muted-foreground italic">unknown</span>
                  <% c -> %>
                    <.link
                      navigate={~p"/customers/#{c.id}"}
                      class="relative z-10 text-foreground font-medium hover:text-primary transition-colors duration-[var(--motion-fast)]"
                    >
                      {display_name(c)}
                    </.link>
                <% end %>
              </td>
              <td class="px-4 py-2.5 align-middle">
                <span class="relative"><.phone phone={call.from_phone} /></span>
              </td>
              <td class="px-4 py-2.5 align-middle">
                <span class="relative"><.status_pill status={call.status} /></span>
              </td>
              <td class="px-4 py-2.5 align-middle mono text-muted-foreground tabular-nums">
                <span class="relative">{duration(call)}</span>
              </td>
              <td class="px-4 py-2.5 align-middle">
                <span class="relative">{sentiment_glyph(call.sentiment_score)}</span>
              </td>
              <td class="px-4 py-2.5 align-middle text-right">
                <div class="relative z-10 flex items-center justify-end gap-3">
                  <%= if live?(call) do %>
                    <.alert_dialog id={"end-call-#{call.id}"}>
                      <.alert_dialog_trigger>
                        <button
                          type="button"
                          class="text-destructive font-medium hover:text-destructive/80 transition-colors duration-[var(--motion-fast)] cursor-pointer"
                          aria-label="End this live call"
                        >
                          end ×
                        </button>
                      </.alert_dialog_trigger>
                      <.alert_dialog_content>
                        <.alert_dialog_header>
                          <.alert_dialog_title>End this call?</.alert_dialog_title>
                          <.alert_dialog_description>
                            The caller will be disconnected immediately. This can't be undone.
                          </.alert_dialog_description>
                        </.alert_dialog_header>
                        <.alert_dialog_footer>
                          <.alert_dialog_cancel>Cancel</.alert_dialog_cancel>
                          <.alert_dialog_action
                            variant="destructive"
                            phx-click="end_call"
                            phx-value-ccid={call.provider_id}
                            data-action="close"
                          >
                            End call
                          </.alert_dialog_action>
                        </.alert_dialog_footer>
                      </.alert_dialog_content>
                    </.alert_dialog>
                  <% end %>
                  <span class="text-primary font-medium" aria-hidden="true">open →</span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </.panel>
    </div>
    """
  end

  defp org_suffix(nil), do: ""
  defp org_suffix(org), do: " for #{org.name}"

  defp live_row_class(%{status: status}) do
    cond do
      status == Constants.status_active() -> "bg-success-soft/40"
      status == Constants.status_ringing() -> "bg-accent/40"
      true -> ""
    end
  end

  # is this call still live? gates the "end ×" button — only show it
  # when there's actually something to end. ringing + active are the
  # two non-terminal statuses; everything else is already over.
  defp live?(%{status: status}) do
    status in [Constants.status_ringing(), Constants.status_active()]
  end

  # short HH:MM:SS or MM:SS for the call duration, or "live" for an
  # in-progress one. nil started_at → em-dash.
  defp duration(%{started_at: nil}), do: "—"

  defp duration(%{started_at: started, ended_at: nil}) do
    secs = max(DateTime.diff(DateTime.utc_now(), started), 0)
    "live · " <> format_secs(secs)
  end

  defp duration(%{started_at: started, ended_at: ended}) do
    secs = max(DateTime.diff(ended, started), 0)
    format_secs(secs)
  end

  defp format_secs(secs) when secs < 3600 do
    minutes = div(secs, 60)
    seconds = rem(secs, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, seconds]) |> IO.iodata_to_binary()
  end

  defp format_secs(secs) do
    hours = div(secs, 3600)
    minutes = div(rem(secs, 3600), 60)
    seconds = rem(secs, 60)
    :io_lib.format("~B:~2..0B:~2..0B", [hours, minutes, seconds]) |> IO.iodata_to_binary()
  end

  # tiny ascii-style sentiment glyph. score is -1..+1, nil if not scored.
  defp sentiment_glyph(nil), do: assigns_span("text-muted-foreground", "·")

  defp sentiment_glyph(score) when is_float(score) do
    cond do
      score >= 0.3 -> assigns_span("text-success", "▲")
      score <= -0.3 -> assigns_span("text-destructive", "▼")
      true -> assigns_span("text-muted-foreground", "—")
    end
  end

  defp assigns_span(class, char) do
    Phoenix.HTML.raw(~s|<span class="font-mono #{class}" aria-hidden="true">#{char}</span>|)
  end
end
