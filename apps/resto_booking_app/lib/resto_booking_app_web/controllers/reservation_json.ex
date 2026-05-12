defmodule RestoBookingAppWeb.ReservationJSON do
  @moduledoc """
  json shapes for reservations. `public/1` is what the index endpoint emits
  (booking + the linked customer summary). `with_token/1` is the same plus
  the cancel_token, returned only on create — that's the single moment the
  booker gets to capture it.

  guest contact details (name, tel, email, salutation) live on the linked
  customer now. the reservation embeds a small customer object when the
  association is preloaded; otherwise just the customer_id string.
  """

  use RestoBookingAppWeb, :json

  alias RestoBookingApp.Reservations.Reservation
  alias RestoBookingAppWeb.{ContactJSON, CustomerJSON}

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
      starts_at: iso8601(res.starts_at),
      ends_at: iso8601(res.ends_at),
      party_size: res.party_size,
      special_requests: res.special_requests,
      remarks: res.remarks,
      customer_id: res.customer_id,
      customer: customer_payload(res.customer),
      contact_id: res.contact_id,
      contact: contact_payload(res.contact)
    }
  end

  # nil when :customer wasn't preloaded — caller refetches if they need it.
  defp customer_payload(%RestoBookingApp.Customers.Customer{} = c), do: CustomerJSON.public(c)
  defp customer_payload(_), do: nil

  defp contact_payload(%RestoBookingApp.Contacts.Contact{} = c), do: ContactJSON.public(c)
  defp contact_payload(_), do: nil

  defp with_token(%Reservation{} = res) do
    res |> public() |> Map.put(:cancel_token, res.cancel_token)
  end
end
