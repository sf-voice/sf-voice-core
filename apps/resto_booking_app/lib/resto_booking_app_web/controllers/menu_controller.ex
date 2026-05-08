defmodule RestoBookingAppWeb.MenuController do
  use RestoBookingAppWeb, :controller

  alias RestoBookingApp.Menu

  def index(conn, _params) do
    render(conn, :index, menu: Menu.all())
  end
end
