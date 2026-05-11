defmodule RestoBookingAppWeb.AvailabilityController do
  use RestoBookingAppWeb, :controller

  alias RestoBookingApp.{Clock, Reservations}

  action_fallback RestoBookingAppWeb.FallbackController

  def index(conn, params) do
    with {:ok, date} <- parse_date(params["date"]) do
      org_id = conn.assigns.org_id

      render(conn, :index,
        date: date,
        availability: Reservations.availability_for_date(org_id, date)
      )
    end
  end

  defp parse_date(nil), do: {:ok, Clock.today()}

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :bad_date}
    end
  end
end
