defmodule EllieAiWeb.Layouts do
  @moduledoc """
  root + app layouts plus the small components the sidebar reaches for —
  nav links, nav section headers, the org switcher, and flash toasts.

  helpers live next to the embedded templates so the whole staff ui
  shell is one module — easy to read, easy to grep.
  """

  use EllieAiWeb, :html

  # SaladUI.Command isn't in the default `use SaladUI` import set, so we
  # bring it in explicitly here for the org switcher's search palette.
  import SaladUI.Command

  embed_templates "layouts/*"

  # ── nav ────────────────────────────────────────────────────────────────

  @doc """
  labelled group inside the sidebar nav. label is rendered as a small
  uppercase header above the items. set `compact` to halve the vertical
  margin — useful for groups pinned at the sidebar bottom where space
  is at a premium.
  """
  attr :label, :string, required: true
  attr :compact, :boolean, default: false
  slot :inner_block, required: true

  def nav_section(assigns) do
    ~H"""
    <div class={if @compact, do: "mb-0", else: "mb-3"}>
      <div class="px-3 mb-1 text-[10px] uppercase tracking-[0.12em] font-semibold text-muted-foreground">
        {@label}
      </div>
      <ul class="flex flex-col gap-0.5">
        {render_slot(@inner_block)}
      </ul>
    </div>
    """
  end

  @doc """
  single sidebar nav link. active state highlights the row with the
  accent token; `:badge` slot renders a small pill on the right edge.

  density target: ~30px row height to match a Blueprint-style operator
  console (looser than VS Code's 22px, denser than the shadcn default).
  """
  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true
  slot :badge

  def nav_link(assigns) do
    ~H"""
    <li>
      <.link navigate={@to} class={nav_link_class(@active)}>
        <.icon name={@icon} class="h-4 w-4 shrink-0 opacity-80" />
        <span class="flex-1 truncate">{render_slot(@inner_block)}</span>
        <span
          :for={badge <- @badge}
          class="inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-success text-white text-[10px] font-semibold px-1 leading-none"
        >
          {render_slot(badge)}
        </span>
      </.link>
    </li>
    """
  end

  defp nav_link_class(true),
    do:
      "flex items-center gap-2.5 px-3 py-1.5 rounded-md text-[13px] font-medium no-underline " <>
        "bg-accent text-accent-foreground"

  defp nav_link_class(false),
    do:
      "flex items-center gap-2.5 px-3 py-1.5 rounded-md text-[13px] font-medium no-underline " <>
        "text-foreground/85 hover:text-foreground hover:bg-secondary transition-colors"

  # ── org switcher ───────────────────────────────────────────────────────

  @doc """
  org switcher at the top of the sidebar. popover + cmdk-style command
  palette so an operator with many orgs can type to filter instead of
  scrolling.

  shape:
    * trigger button = current org's initials + name + slug
    * popover content sized to the trigger so it stays inside the sidebar
    * search input + filterable list (filter is client-side, no roundtrip)
    * each row is a real POST form so the switch still works with JS off

  width is pinned with an inline `--switcher-w` so the trigger and the
  popover always match — keeps the dropdown from spilling past the
  sidebar's right edge.
  """
  attr :current, :any, required: true
  attr :orgs, :list, required: true
  attr :csrf, :string, required: true

  def org_switcher(assigns) do
    ~H"""
    <.popover id="ellie-org-switcher">
      <.popover_trigger class="block w-full">
        <button
          type="button"
          title={if @current, do: @current.name}
          class="group w-full max-w-full flex items-center gap-2 min-w-0 px-2 py-1.5 rounded-md border border-transparent bg-transparent text-left hover:bg-secondary hover:border-sidebar-border data-[state=open]:bg-secondary data-[state=open]:border-sidebar-border transition-all duration-[var(--motion-fast)] ease-[var(--motion-ease)] overflow-hidden"
        >
          <span class="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded bg-primary text-primary-foreground text-[11px] font-semibold tracking-tight shadow-[var(--shadow-xs)]">
            {org_initials(@current)}
          </span>
          <span class="flex flex-col items-start min-w-0 flex-1 overflow-hidden">
            <span class="text-[13px] font-semibold text-foreground truncate max-w-full leading-tight">
              {org_label(@current)}
            </span>
            <span :if={@current} class="font-mono text-[10px] text-muted-foreground truncate max-w-full leading-tight">
              {@current.slug}
            </span>
          </span>
          <.icon
            name="hero-chevron-up-down"
            class="h-3.5 w-3.5 text-muted-foreground shrink-0 group-hover:text-foreground transition-colors duration-[var(--motion-fast)]"
          />
        </button>
      </.popover_trigger>

      <.popover_content
        side="bottom"
        align="start"
        side-offset={4}
        class="w-72 p-0 overflow-hidden border-border shadow-[var(--shadow-md)]"
      >
        <.command id="ellie-org-search" class="ellie-cmd-root">
          <.command_input
            placeholder="Search organizations"
            class="ellie-cmd-input"
          />

          <.command_empty class="px-3 py-5 text-center text-xs text-muted-foreground italic">
            No matches.
          </.command_empty>

          <.command_list class="max-h-[280px] py-1">
            <form
              :for={org <- @orgs}
              action="/org/switch"
              method="post"
              class="contents"
              data-org-name={org.name}
              data-org-slug={org.slug}
            >
              <input type="hidden" name="_csrf_token" value={@csrf} />
              <input type="hidden" name="org_id" value={org.id} />
              <.command_item
                type="submit"
                class={"ellie-cmd-item mx-1 my-0 px-2 py-1.5 gap-2 cursor-pointer items-center " <>
                  if(@current && @current.id == org.id, do: "is-current", else: "")}
              >
                <span class="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded bg-secondary text-foreground text-[10px] font-semibold tracking-tight">
                  {org_initials(org)}
                </span>
                <span class="flex flex-col items-start min-w-0 flex-1 leading-tight">
                  <span class="text-[13px] font-medium text-foreground truncate max-w-full">{org.name}</span>
                  <span class="font-mono text-[10px] text-muted-foreground truncate max-w-full">{org.slug}</span>
                </span>
                <.icon
                  :if={@current && @current.id == org.id}
                  name="hero-check"
                  class="h-3.5 w-3.5 text-primary shrink-0"
                />
              </.command_item>
            </form>
          </.command_list>
        </.command>
      </.popover_content>
    </.popover>
    """
  end

  defp org_label(nil), do: "No organization"
  defp org_label(org), do: org.name

  defp org_initials(nil), do: "—"

  defp org_initials(%{name: name}) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp org_initials(_), do: "—"

  # ── flash toasts ───────────────────────────────────────────────────────

  @doc """
  flash messages as top-right toasts so they don't push the page content
  down. auto-dismiss is wired client-side via a tiny `phx-hook="Toast"`
  in app.js (5s linger). dismiss button covers users with reduced motion.
  """
  attr :flash, :map, required: true

  def flash_toasts(assigns) do
    ~H"""
    <div
      :if={Phoenix.Flash.get(@flash, :info) || Phoenix.Flash.get(@flash, :error)}
      class="fixed top-4 right-4 z-50 flex flex-col gap-2 max-w-sm pointer-events-none"
      aria-live="polite"
      aria-atomic="true"
    >
      <div
        :if={msg = Phoenix.Flash.get(@flash, :info)}
        id="flash-info"
        phx-hook="Toast"
        phx-click={JS.exec("phx-remove", to: "#flash-info") |> JS.push("lv:clear-flash", value: %{key: "info"})}
        class="pointer-events-auto rounded-md border border-success bg-card shadow-md px-3 py-2 text-sm text-foreground flex items-start gap-2 cursor-pointer"
        role="status"
      >
        <.icon name="hero-check-circle" class="h-4 w-4 text-success shrink-0 mt-0.5" />
        <span class="flex-1">{msg}</span>
      </div>
      <div
        :if={msg = Phoenix.Flash.get(@flash, :error)}
        id="flash-error"
        phx-hook="Toast"
        phx-click={JS.exec("phx-remove", to: "#flash-error") |> JS.push("lv:clear-flash", value: %{key: "error"})}
        class="pointer-events-auto rounded-md border border-destructive bg-card shadow-md px-3 py-2 text-sm text-foreground flex items-start gap-2 cursor-pointer"
        role="alert"
      >
        <.icon name="hero-exclamation-triangle" class="h-4 w-4 text-destructive shrink-0 mt-0.5" />
        <span class="flex-1">{msg}</span>
      </div>
    </div>
    """
  end
end
