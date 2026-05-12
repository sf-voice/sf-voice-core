defmodule EllieAiWeb.AdminNav do
  @moduledoc """
  secondary nav strip rendered at the top of every admin subpage. lets
  the operator jump sideways without going back to the hub.

  current page is highlighted; everything else dims to muted. matches the
  density and type scale of the main sidebar so the visual language
  carries from one nav surface to the other.
  """

  use Phoenix.Component
  use EllieAiWeb, :verified_routes

  import SaladUI.Icon

  attr :current, :atom, required: true, doc: "one of :hub :orgs :runtime :skills"

  def render(assigns) do
    ~H"""
    <nav
      aria-label="Admin sections"
      class="flex items-center gap-1 border-b border-border pb-2"
    >
      <.tab to={~p"/admin"} active={@current == :hub} icon="hero-squares-2x2">
        Hub
      </.tab>
      <.tab to={~p"/admin/organizations"} active={@current == :orgs} icon="hero-building-office-2">
        Organizations
      </.tab>
      <.tab to={~p"/admin/runtime"} active={@current == :runtime} icon="hero-adjustments-horizontal">
        Runtime
      </.tab>
      <.tab to={~p"/admin/skills"} active={@current == :skills} icon="hero-puzzle-piece">
        Skills
      </.tab>
    </nav>
    """
  end

  attr :to, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <.link navigate={@to} class={tab_class(@active)}>
      <.icon name={@icon} class="h-3.5 w-3.5 opacity-80" />
      <span>{render_slot(@inner_block)}</span>
    </.link>
    """
  end

  defp tab_class(true),
    do:
      "flex items-center gap-1.5 px-3 py-1.5 rounded-md text-[13px] font-medium no-underline " <>
        "bg-accent text-accent-foreground"

  defp tab_class(false),
    do:
      "flex items-center gap-1.5 px-3 py-1.5 rounded-md text-[13px] font-medium no-underline " <>
        "text-muted-foreground hover:text-foreground hover:bg-secondary transition-colors duration-[var(--motion-fast)]"
end
