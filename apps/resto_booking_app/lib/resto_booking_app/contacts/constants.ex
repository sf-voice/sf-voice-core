defmodule RestoBookingApp.Contacts.Constants do
  @moduledoc """
  shared contacts constants. canonical list of valid `kind` values plus
  named accessors for the two we look up by name from other modules.

  pattern matches inside `Contact` itself still use string literals —
  you can't pattern-match against a function call. those literals are
  acknowledged as matching the values returned here.
  """

  def kinds, do: ~w(phone email sms)
  def phone, do: "phone"
  def email, do: "email"
end
