defmodule RestoBookingAppWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RestoBookingAppWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :org, :any,
    default: nil,
    doc:
      "the org currently in scope (set by floor_plan / menu views). when nil, " <>
        "the org-scoped nav links (Floor plan, Menu) are hidden — used on the " <>
        "landing + /api pages which have no single restaurant context."

  attr :active, :atom,
    default: nil,
    doc:
      "marker for which org-scoped nav link should render as active. one of " <>
        "`:floor_plan`, `:menu`, or `nil`."

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="px-4 sm:px-6 lg:px-10 pt-6 lg:pt-3">
      <nav class="mx-auto max-w-7xl flex items-center justify-between gap-3 flex-wrap">
        <a href="/" class="flex flex-col leading-none">
          <span class="font-display text-2xl sm:text-3xl lg:text-2xl uppercase tracking-[0.2em] text-primary">
            The Seasons
          </span>
          <span class="text-[10px] uppercase tracking-[0.25em] opacity-50 mt-1">
            Reservations Desk
          </span>
        </a>
        <div class="flex items-center gap-2">
          <%= if @org do %>
            <.link
              href={"/#{@org.slug}/floor_plan"}
              class={nav_link_class(@active == :floor_plan)}
            >
              Floor plan
            </.link>
            <.link
              href={"/#{@org.slug}/menu"}
              class={nav_link_class(@active == :menu)}
            >
              Menu
            </.link>
          <% end %>
          <.link
            href="/api"
            class="btn btn-ghost btn-sm uppercase tracking-widest text-xs"
          >
            API
          </.link>
          <.theme_toggle />
        </div>
      </nav>
      <div class="mx-auto max-w-7xl mt-3 lg:mt-2">
        <div class="h-px bg-base-300"></div>
      </div>
    </header>

    <main class="px-4 sm:px-6 lg:px-10 pt-6 lg:pt-4 pb-12 lg:pb-2">
      <div class="mx-auto max-w-7xl">
        {render_slot(@inner_block)}
      </div>
    </main>

    <footer class="px-4 sm:px-6 lg:px-10 pb-6 lg:pb-2">
      <div class="mx-auto max-w-7xl border-t border-base-300 pt-3 lg:pt-2 text-[11px] opacity-60 leading-relaxed text-center">
        The Seasons · a prodigy demo project · no actual reservations are held
      </div>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  # active state = same button as the inactive one but with `text-primary`
  # so the current page is obviously the current page without breaking the
  # button's tap target or alignment. low-tech users notice colour, not
  # weight or underline.
  defp nav_link_class(true),
    do: "btn btn-ghost btn-sm uppercase tracking-widest text-xs text-primary font-bold"

  defp nav_link_class(false),
    do: "btn btn-ghost btn-sm uppercase tracking-widest text-xs"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/2 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=dark]_&]:left-1/2 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
