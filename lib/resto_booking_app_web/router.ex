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

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RestoBookingAppWeb do
    pipe_through :browser

    # the floor plan is the landing page — no sign-in, no marketing splash
    live "/", FloorPlanLive, :index
  end

  scope "/api", RestoBookingAppWeb do
    pipe_through :api

    get "/menu", MenuController, :index
    get "/tables", TableController, :index
    get "/availability", AvailabilityController, :index

    resources "/reservations", ReservationController,
      only: [:index, :show, :create, :update, :delete]
  end
end
