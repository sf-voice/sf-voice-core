defmodule RestoBookingAppWeb.MenuLive do
  @moduledoc """
  read-only menu for one restaurant. groups items by service
  (breakfast / lunch / dinner) and shows name, price, and dietary tags
  for each.

  no editing, no booking flow — the page exists so guests browsing the
  floor plan can glance at what's on offer before they reserve. staff
  can also point a caller at it during a phone call ("see our menu at
  the-seasons.example/seasons-sf/menu").

  redirects to `/` when the org_slug is unknown so a typo in the URL
  bar doesn't 500.
  """

  use RestoBookingAppWeb, :live_view

  alias RestoBookingApp.{Menu, Orgs}
  alias RestoBookingApp.MenuItems.MenuItem

  @impl true
  def mount(%{"org_slug" => slug}, _session, socket) do
    case Orgs.get_by_slug(slug) do
      nil ->
        {:ok, redirect(socket, to: "/")}

      org ->
        # Menu.all/1 returns %{breakfast: [...], lunch: [...], dinner: [...]}
        # with empty lists for services that have no items yet, so we can
        # iterate the canonical service order without nil checks.
        {:ok,
         socket
         |> assign(:org, org)
         |> assign(:menu, Menu.all(org.id))
         |> assign(:page_title, "Menu — #{org.name}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} org={@org} active={:menu}>
      <section class="mb-6 lg:mb-3">
        <p class="text-[10px] uppercase tracking-[0.3em] text-primary opacity-70 mb-1">
          {@org.name}
        </p>
        <h1 class="font-display text-2xl lg:text-xl text-base-content leading-tight">
          Menu
        </h1>
      </section>

      <div class="space-y-6 lg:space-y-4">
        <%= for service <- Menu.services() do %>
          <.service_section service={service} items={Map.get(@menu, service, [])} />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # one card per service. quiet "no items yet" state when an org hasn't
  # added anything for a given service — guests still see the section
  # so the absence is obvious, not the result hidden.
  attr :service, :atom, required: true
  attr :items, :list, required: true

  defp service_section(assigns) do
    ~H"""
    <section class="rounded-2xl bg-base-100/80 backdrop-blur border border-base-300 shadow-sm overflow-hidden">
      <header class="px-4 sm:px-5 py-3 border-b border-base-300 flex items-baseline justify-between gap-3">
        <h2 class="font-display text-xl lg:text-lg capitalize">{@service}</h2>
        <span class="text-[10px] uppercase tracking-[0.2em] opacity-60">
          {length(@items)} {pluralize_items(length(@items))}
        </span>
      </header>

      <div :if={@items == []} class="px-4 sm:px-5 py-8 text-center text-sm opacity-60 italic">
        No items on the {@service} menu yet.
      </div>

      <ul :if={@items != []} class="divide-y divide-base-300">
        <li
          :for={item <- @items}
          class="px-4 sm:px-5 py-3 grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 items-baseline"
        >
          <div class="font-semibold text-base-content">{item.name}</div>
          <div class="font-mono tabular-nums text-sm">{format_price(item.price_cents)}</div>
          <div :if={dietary_list(item) != []} class="col-span-2 flex flex-wrap gap-1.5">
            <span
              :for={tag <- dietary_list(item)}
              class="inline-flex items-center rounded-full bg-secondary/20 text-secondary text-[10px] uppercase tracking-wider font-semibold px-2 py-0.5"
            >
              {humanize_tag(tag)}
            </span>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp dietary_list(%MenuItem{} = item), do: MenuItem.dietary_list(item)

  # format a price stored as integer cents into "$12.00". keeping it
  # ASCII + USD-only is deliberate for v0 — the restaurant is in SF, no
  # currency switching needed yet.
  defp format_price(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    rem_cents = rem(cents, 100)
    :io_lib.format("$~B.~2..0B", [dollars, rem_cents]) |> IO.iodata_to_binary()
  end

  defp format_price(_), do: "—"

  # tags come in as atoms via MenuItem.dietary_list/1 — `:gluten_free`
  # becomes "gluten free" for display so the pills read naturally.
  defp humanize_tag(tag) when is_atom(tag) do
    tag |> Atom.to_string() |> String.replace("_", " ")
  end

  defp humanize_tag(tag) when is_binary(tag), do: String.replace(tag, "_", " ")
  defp humanize_tag(_), do: ""

  defp pluralize_items(1), do: "item"
  defp pluralize_items(_), do: "items"
end
