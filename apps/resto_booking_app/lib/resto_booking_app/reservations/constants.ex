defmodule RestoBookingApp.Reservations.Constants do
  @moduledoc """
  shared reservation constants — values referenced by both the
  `Reservation` schema and the floor-plan liveview. constants used only
  inside `Reservation` itself stay there as a `@module_attribute`.
  """

  # 30-minute slot grid
  def slot_minutes, do: 30

  # last bookable start (20:00 in minutes-since-midnight). anything later
  # would push the 2-hour block past the 22:00 close.
  def last_start_minutes, do: 20 * 60
end
