defmodule RestoBookingApp.Clock do
  @moduledoc """
  single source of truth for the restaurant's local time.

  every human-facing date/time decision — opening-hours validation, the
  floor-plan day filter, slot construction — should go through here.
  storage stays in utc; this module only governs interpretation.

  the timezone comes from `config :resto_booking_app, :timezone, ...`
  and defaults to america/los_angeles.
  """

  @default_tz "America/Los_Angeles"

  @doc "the restaurant's configured iana timezone"
  def timezone do
    Application.get_env(:resto_booking_app, :timezone, @default_tz)
  end

  @doc "today's date in the restaurant's local zone"
  def today do
    timezone()
    |> DateTime.now!()
    |> DateTime.to_date()
  end

  @doc """
  build a utc datetime from a local date+time. raises if the local time
  doesn't exist (e.g. the spring-forward gap) or is ambiguous (fall-back).
  for our 30-min slot grid the bookable window (06:00–22:00) sits well
  outside any DST transition, so this is safe in practice.
  """
  def local_to_utc(%Date{} = date, %Time{} = time) do
    {:ok, local} = DateTime.new(date, time, timezone())
    DateTime.shift_zone!(local, "Etc/UTC")
  end

  @doc "shift a utc datetime into the restaurant's local zone"
  def to_local(%DateTime{} = dt) do
    DateTime.shift_zone!(dt, timezone())
  end
end
