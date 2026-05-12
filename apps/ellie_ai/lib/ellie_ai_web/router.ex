defmodule EllieAiWeb.Router do
  use EllieAiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EllieAiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # resolves and persists :current_org_id in session so every controller
    # action and every LiveView mount share the same active org. must run
    # after :fetch_session.
    plug EllieAiWeb.Plugs.OrgSession
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :internal_api do
    plug :accepts, ["json"]
    plug EllieAiWeb.Plugs.InternalAuth
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
    live "/calls", CallsLive, :index
    live "/calls/:id", CallDetailLive, :show
    get "/calls/:id/audio", CallAudioController, :show
    live "/settings", SettingsLive, :index
    live "/admin", AdminLive, :index
    live "/admin/organizations", AdminOrganizationsLive, :index
    live "/admin/runtime", AdminRuntimeLive, :index
    live "/admin/skills", AdminSkillsLive, :index

    post "/org/switch", OrgSwitchController, :switch
  end

  scope "/admin", EllieAiWeb do
    pipe_through :internal_api

    post "/drain", AdminDrainController, :drain
  end

  scope "/health", EllieAiWeb do
    pipe_through :api

    get "/", HealthController, :show
    get "/active_calls", HealthController, :active_calls
  end

  scope "/telnyx", EllieAiWeb do
    pipe_through :telnyx_webhook
    post "/webhook", TelnyxWebhookController, :handle
    post "/messages", TelnyxMessageWebhookController, :handle
  end

  scope "/telnyx", EllieAiWeb do
    pipe_through :telnyx_websocket
    get "/media-streaming", MediaStreamingController, :upgrade
  end
end
