defmodule RestoBookingAppWeb.TableController do
  use RestoBookingAppWeb, :controller

  alias RestoBookingApp.Tables

  def index(conn, _params) do
    render(conn, :index, tables: Tables.all(), seat_total: Tables.seat_total())
  end
end
