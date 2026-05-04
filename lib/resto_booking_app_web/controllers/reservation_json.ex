defmodule RestoBookingAppWeb.ReservationJSON do
  @moduledoc """
  json shapes for reservations. `public/1` is what the floor plan and the
  list endpoint emit (everyone sees names + dietary). `with_token/1` is the
  same plus the cancel_token, returned only on create — that's the single
  moment the booker gets to capture it.
  """

  alias RestoBookingApp.Reservations.Reservation

  def index(%{reservations: reservations}) do
    %{reservations: Enum.map(reservations, &public/1)}
  end

  def show(%{reservation: %Reservation{} = res, with_token: true}) do
    %{reservation: with_token(res)}
  end

  def show(%{reservation: %Reservation{} = res}) do
    %{reservation: public(res)}
  end

  def public(%Reservation{} = res) do
    %{
      id: res.id,
      table_id: res.table_id,
      starts_at: format_dt(res.starts_at),
      ends_at: format_dt(res.ends_at),
      name: res.name,
      dietary: res.dietary,
      notes: res.notes,
      party_size: res.party_size
    }
  end

  defp with_token(%Reservation{} = res) do
    res |> public() |> Map.put(:cancel_token, res.cancel_token)
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
