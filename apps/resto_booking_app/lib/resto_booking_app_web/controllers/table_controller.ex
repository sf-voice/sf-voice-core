defmodule RestoBookingAppWeb.TableController do
  use RestoBookingAppWeb, :controller

  alias RestoBookingApp.Tables

  def index(conn, _params) do
    org_id = conn.assigns.org_id
    render(conn, :index, tables: Tables.all(org_id), seat_total: Tables.seat_total(org_id))
  end
end
