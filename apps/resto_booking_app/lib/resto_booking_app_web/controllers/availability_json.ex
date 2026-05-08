defmodule RestoBookingAppWeb.AvailabilityJSON do
  @moduledoc "per-table list of taken intervals for a given date"

  alias RestoBookingAppWeb.ReservationJSON

  def index(%{date: date, availability: availability}) do
    %{
      date: Date.to_iso8601(date),
      tables:
        availability
        |> Enum.sort_by(fn {table_id, _} -> table_id end)
        |> Enum.map(fn {table_id, reservations} ->
          %{
            table_id: table_id,
            reservations: Enum.map(reservations, &ReservationJSON.public/1)
          }
        end)
    }
  end
end
