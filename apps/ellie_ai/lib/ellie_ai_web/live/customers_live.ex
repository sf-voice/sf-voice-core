defmodule EllieAiWeb.CustomersLive do
  @moduledoc """
  homepage. two stacked sections per design review pass 1A:

    * live calls (top, dominant) — subscribed to the `calls:lifecycle`
      pubsub topic, rerenders when ringing/active/ended events fire.
    * customer list (below) — recent customers from the local
      customer_summary mirror table.

  the active org comes from `socket.assigns.nav_org` (populated by
  EllieAiWeb.LiveNav from session). switching org in the sidebar
  re-mounts and re-loads here.
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
     |> assign(:page_title, "Customers")
     |> assign(:active_nav, :customers)
     |> assign(:editing_id, nil)
     |> load_data()}
  end

  @impl true
  def handle_info({:call_changed, _payload}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("start_edit_name", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_id, id)}
  end

  def handle_event("cancel_edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  def handle_event("save_name", %{"customer_id" => id, "name" => raw}, socket),
    do: save_name(socket, id, raw)

  def handle_event("save_name", %{"id" => id, "value" => raw}, socket),
    do: save_name(socket, id, raw)

  defp save_name(socket, id, raw) do
    org = socket.assigns.nav_org
    {first, last} = Customers.split_name(raw)

    attrs = %{first_name: first, last_name: last}

    case Customers.update_by_id(org.id, id, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:editing_id, nil)
         |> load_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:editing_id, nil)
         |> put_flash(:error, "Couldn't save: #{inspect(reason)}")}
    end
  end

  # active org comes from EllieAiWeb.LiveNav (session-backed). every page
  # reads `:nav_org` and renders nil-safely so the empty-org state is
  # still legible.
  defp load_data(socket) do
    case socket.assigns[:nav_org] do
      nil ->
        socket
        |> assign(:org, nil)
        |> assign(:live_calls, [])
        |> assign(:customers, [])

      org ->
        live_calls =
          org.id
          |> Calls.list_recent(20)
          |> Enum.filter(&(&1.status in [Constants.status_ringing(), Constants.status_active()]))

        customers = Customers.list(org.id, limit: 50)

        socket
        |> assign(:org, org)
        |> assign(:live_calls, live_calls)
        |> assign(:customers, customers)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.empty_state
      :if={is_nil(@org)}
      icon="hero-building-office-2"
      title="No org configured"
    >
      <:description>
        Run <code class="mono">mix run priv/repo/seeds.exs</code> in
        <code class="mono">apps/ellie_ai</code> to seed a demo org.
      </:description>
    </.empty_state>

    <div :if={@org} class="space-y-6">
      <.page_header title="Customers">
        <:subtitle>
          Who's called {@org.name}, and what's live right now.
        </:subtitle>
      </.page_header>

      <.panel elevated>
        <:header>
          <h2 class="text-sm font-semibold text-foreground flex items-center gap-2">
            <span :if={@live_calls != []} class="inline-block h-2 w-2 rounded-full bg-success animate-pulse" aria-hidden="true"></span>
            Live calls
            <span class="font-mono text-xs text-muted-foreground">{length(@live_calls)}</span>
          </h2>
          <.link navigate={~p"/calls"} class="text-xs text-primary font-medium hover:text-primary-hover transition-colors duration-[var(--motion-fast)]">
            All calls →
          </.link>
        </:header>

        <.list_empty :if={@live_calls == []}>
          No active calls.
        </.list_empty>

        <ul :if={@live_calls != []} class="divide-y divide-border">
          <li
            :for={call <- @live_calls}
            class="bg-success-soft/40 hover:bg-success-soft/60 transition-colors duration-[var(--motion-fast)]"
          >
            <.link
              navigate={~p"/calls/#{call.id}"}
              class="block px-5 py-3 flex items-center justify-between gap-4"
              aria-label={"Open live call from " <> (call.from_phone || "unknown")}
            >
              <div class="flex items-center gap-3 min-w-0">
                <.status_pill status={call.status} />
                <.phone phone={call.from_phone} />
                <span class="text-muted-foreground" aria-hidden="true">→</span>
                <.phone phone={call.to_phone} />
              </div>
              <div class="flex items-center gap-4 shrink-0">
                <.datetime at={call.started_at} format={:time} />
                <span
                  class="text-sm text-primary font-medium"
                  aria-hidden="true"
                >Open →</span>
              </div>
            </.link>
          </li>
        </ul>
      </.panel>

      <.panel elevated>
        <:header>
          <h2 class="text-sm font-semibold text-foreground">
            Customers <span class="font-mono text-xs text-muted-foreground">{length(@customers)}</span>
          </h2>
        </:header>

        <.list_empty :if={@customers == []}>
          No customers yet. They'll appear here as they call.
        </.list_empty>

        <ul :if={@customers != []} class="divide-y divide-border">
          <li
            :for={c <- @customers}
            class="px-5 py-2.5 grid grid-cols-[1fr_1fr_1fr_auto] gap-3 items-center hover:bg-secondary/60 transition-colors duration-[var(--motion-fast)]"
          >
            <.editable_name customer={c} editing?={@editing_id == c.id} />

            <.link
              navigate={~p"/customers/#{c.id}"}
              class="text-foreground hover:text-primary transition-colors duration-[var(--motion-fast)]"
            >
              <.phone phone={c.phone_e164} />
            </.link>

            <div class="mono text-xs text-muted-foreground">
              <span :if={c.last_seen_at}>last seen <.datetime at={c.last_seen_at} /></span>
            </div>

            <.link
              navigate={~p"/customers/#{c.id}"}
              class="text-sm text-primary font-medium hover:text-primary-hover transition-colors duration-[var(--motion-fast)] justify-self-end"
            >
              open →
            </.link>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end

end
