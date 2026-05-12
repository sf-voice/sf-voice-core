defmodule RestoBookingAppWeb.ContactJSON do
  @moduledoc """
  json shape for contacts. one shape, no public/private split — all callers
  are bearer-authed.
  """

  alias RestoBookingApp.Contacts.Contact

  def index(%{contacts: contacts}) do
    %{contacts: Enum.map(contacts, &public/1)}
  end

  def show(%{contact: %Contact{} = contact}) do
    %{contact: public(contact)}
  end

  def public(%Contact{} = c) do
    %{
      id: c.id,
      customer_id: c.customer_id,
      kind: c.kind,
      value: c.value,
      label: c.label,
      preferred: c.preferred
    }
  end
end
