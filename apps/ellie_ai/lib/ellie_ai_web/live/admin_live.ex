defmodule EllieAiWeb.AdminLive do
  @moduledoc """
  admin hub. lands at `/admin` and shows a card per sub-section:

    * organizations — create / manage orgs (`/admin/organizations`)
    * runtime       — per-org call-loop knobs (`/admin/runtime`)
    * skills        — list & test the tools the AI can invoke (`/admin/skills`)

  developer / operator surface — deliberately not exposed in the main
  sidebar's "Settings" route. the customer-facing `/settings` keeps the
  org identity + integrations there.
  """

  use EllieAiWeb, :live_view

  alias EllieAi.{Orgs, Tools}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:active_nav, :admin)
     |> assign_counts()}
  end

  defp assign_counts(socket) do
    socket
    |> assign(:org_count, length(Orgs.list()))
    |> assign(:tool_count, length(Tools.list()))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.page_header title="Admin">
        <:subtitle>
          Developer tools. Not part of the customer-facing console.
        </:subtitle>
      </.page_header>

      <EllieAiWeb.AdminNav.render current={:hub} />

      <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
        <.admin_card
          to={~p"/admin/organizations"}
          icon="hero-building-office-2"
          title="Organizations"
          metric={"#{@org_count} configured"}
        >
          Add a new restaurant, edit identity details, or hand off the
          Telnyx number after you buy it.
        </.admin_card>

        <.admin_card
          to={~p"/admin/runtime"}
          icon="hero-adjustments-horizontal"
          title="Runtime"
          metric="vad · voice · model"
        >
          Per-org knobs that flow into the call loop on a 30s cache TTL.
          Touch with care — wrong values break inbound calls.
        </.admin_card>

        <.admin_card
          to={~p"/admin/skills"}
          icon="hero-puzzle-piece"
          title="Skills"
          metric={"#{@tool_count} tool#{if @tool_count == 1, do: "", else: "s"}"}
        >
          Inspect the function tools the realtime session can call, and
          run them by hand to confirm wiring before a real call.
        </.admin_card>
      </div>
    </div>
    """
  end

  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :metric, :string, required: true
  slot :inner_block, required: true

  defp admin_card(assigns) do
    ~H"""
    <.link
      navigate={@to}
      class="group block rounded-md border border-border bg-card p-5 no-underline shadow-[var(--shadow-xs)] hover:shadow-[var(--shadow-sm)] hover:border-primary/40 transition-all duration-[var(--motion-base)] ease-[var(--motion-ease)]"
    >
      <div class="flex items-center gap-3">
        <span class="inline-flex h-9 w-9 items-center justify-center rounded bg-accent text-accent-foreground">
          <.icon name={@icon} class="h-5 w-5" />
        </span>
        <div class="flex-1 min-w-0">
          <h3 class="text-[15px] font-semibold text-foreground">{@title}</h3>
          <p class="text-xs font-mono text-muted-foreground">{@metric}</p>
        </div>
        <.icon
          name="hero-arrow-right"
          class="h-4 w-4 text-muted-foreground group-hover:text-primary group-hover:translate-x-0.5 transition-all duration-[var(--motion-base)] ease-[var(--motion-ease)]"
        />
      </div>
      <p class="mt-3 text-sm text-muted-foreground">
        {render_slot(@inner_block)}
      </p>
    </.link>
    """
  end
end
