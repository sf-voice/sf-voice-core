defmodule RestoBookingApp.Validations do
  @moduledoc """
  cross-context validation regexes. lives at the top of the namespace
  because both `Bookings` and `Contacts` need the same E.164 / email
  shape gates and shouldn't depend on each other.
  """

  # E.164: leading + then 7..15 digits, first non-zero. ex_phone_number
  # normalizes at the boundary; this regex is the final shape gate.
  def e164_regex, do: ~r/^\+[1-9]\d{6,14}$/

  # cheap email shape check — same one we've shown to guests since the
  # booking form first shipped, kept consistent across contexts.
  def email_regex, do: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
end
