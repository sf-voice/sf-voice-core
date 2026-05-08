defmodule EllieAiWeb.Router do
  use EllieAiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", EllieAiWeb do
    pipe_through :api
  end
end
