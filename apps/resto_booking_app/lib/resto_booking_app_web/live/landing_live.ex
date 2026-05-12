defmodule RestoBookingAppWeb.LandingLive do
  @moduledoc """
  the public landing. with multi-tenancy, `/` no longer maps to a
  single restaurant — it lists the orgs hosted on this deploy and
  lets the guest pick one. if there's only one org, redirects
  straight to its floor plan so the previous single-tenant feel is
  preserved for single-restaurant deployments.
  """

  use RestoBookingAppWeb, :live_view

  alias RestoBookingApp.Orgs

  @impl true
  def mount(_params, _session, socket) do
    case Orgs.list() do
      [single] ->
        {:ok, redirect(socket, to: "/#{single.slug}/floor_plan")}

      orgs ->
        {:ok,
         socket
         |> assign(:orgs, orgs)
         |> assign(:page_title, "Welcome")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="max-w-2xl mx-auto py-12">
        <p class="text-[10px] uppercase tracking-[0.3em] text-primary opacity-70 mb-2">
          The Seasons Restaurant Group
        </p>
        <h1 class="font-display text-4xl sm:text-5xl text-base-content leading-tight mb-6">
          Reserve a table
        </h1>
        <p :if={@orgs == []} class="text-sm opacity-70">
          No restaurants are configured yet. Run <code>mix run priv/repo/seeds.exs</code>
          to seed the demo orgs.
        </p>
        <div :if={@orgs != []} class="space-y-3">
          <.link
            :for={org <- @orgs}
            href={"/#{org.slug}/floor_plan"}
            class="block rounded-2xl bg-base-100 border border-base-300 p-5 hover:border-secondary hover:shadow-md transition-all"
          >
            <div class="flex items-baseline justify-between gap-2">
              <span class="font-display text-2xl">{org.name}</span>
            </div>
            <div :if={org.location} class="mt-1 text-sm opacity-70">{org.location}</div>
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
