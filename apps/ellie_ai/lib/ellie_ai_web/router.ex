defmodule EllieAiWeb.Router do
  use EllieAiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EllieAiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end


  pipeline :telnyx_webhook do
    plug :accepts, ["json"]
    plug EllieAi.Telnyx.SignaturePlug
  end

  pipeline :telnyx_websocket do
  end

  scope "/", EllieAiWeb do
    pipe_through :browser

    live "/", CustomersLive, :index
    live "/customers/:id", CustomerDetailLive, :show
    live "/calls/:id", CallDetailLive, :show
    live "/settings", SettingsLive, :index
  end

  scope "/api", EllieAiWeb do
    pipe_through :api
  end

  scope "/telnyx", EllieAiWeb do
    pipe_through :telnyx_webhook
    post "/webhook", TelnyxWebhookController, :handle
  end

  scope "/telnyx", EllieAiWeb do
    pipe_through :telnyx_websocket
    get "/media-streaming", MediaStreamingController, :upgrade
  end
end
