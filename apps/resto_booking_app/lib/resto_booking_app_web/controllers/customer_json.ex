defmodule RestoBookingAppWeb.CustomerJSON do
  @moduledoc """
  json shape for customers. embeds the contacts list when the association
  is preloaded — saves api consumers a second round-trip when they need
  the customer's phone or email alongside their identity.
  """

  use RestoBookingAppWeb, :json

  alias RestoBookingApp.Customers.Customer
  alias RestoBookingAppWeb.ContactJSON

  def index(%{customers: customers}) do
    %{customers: Enum.map(customers, &public/1)}
  end

  def show(%{customer: %Customer{} = customer}) do
    %{customer: public(customer)}
  end

  def public(%Customer{} = c) do
    %{
      id: c.id,
      salutation: c.salutation,
      first_name: c.first_name,
      last_name: c.last_name,
      notes: c.notes,
      first_seen_at: iso8601(c.first_seen_at),
      last_seen_at: iso8601(c.last_seen_at),
      contacts: contacts_payload(c.contacts)
    }
  end

  defp contacts_payload(contacts) when is_list(contacts) do
    Enum.map(contacts, &ContactJSON.public/1)
  end

  defp contacts_payload(_), do: nil
end
