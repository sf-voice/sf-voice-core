defmodule RestoBookingAppWeb.Router do
  use RestoBookingAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RestoBookingAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # bearer-gated via INTERNAL_API_TOKEN; org-scoped downstream by OrgScope.
  pipeline :internal_api do
    plug :accepts, ["json"]
    plug RestoBookingAppWeb.Plugs.InternalAuth
  end

  pipeline :org_scoped do
    plug RestoBookingAppWeb.Plugs.OrgScope
  end

  scope "/", RestoBookingAppWeb do
    pipe_through :browser

    live "/", LandingLive, :index
    live "/api", ApiDocsLive, :index
    live "/:org_slug/floor_plan", FloorPlanLive, :index
    live "/:org_slug/menu", MenuLive, :index
  end

  scope "/api/orgs/:org_slug", RestoBookingAppWeb do
    pipe_through [:internal_api, :org_scoped]

    get "/menu", MenuController, :index
    get "/tables", TableController, :index
    get "/availability", AvailabilityController, :index

    # must precede resources :customers so /:id doesn't swallow "by_phone".
    get "/customers/by_phone/:phone", CustomerController, :show_by_phone
    get "/customers/:customer_id/reservations", ReservationController, :index

    resources "/customers", CustomerController, only: [:index, :show, :create, :update]

    resources "/reservations", ReservationController,
      only: [:index, :show, :create, :update, :delete]
  end
end
