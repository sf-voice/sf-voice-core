# demo bookings spread across yesterday, today, and the next two days so the
# floor plan is never empty on first load. safe to run repeatedly: we wipe
# every reservation that matches the seed window before re-inserting, so
# running `RestoBookingApp.Release.seed/0` on each deploy keeps the demo
# fresh without ever piling up duplicates.

import Ecto.Query

alias RestoBookingApp.{Clock, Repo, Reservations}
alias RestoBookingApp.Reservations.Reservation

today = Clock.today()

# four-day rolling window: yesterday → today → +1 → +2.
window_dates = [
  Date.add(today, -1),
  today,
  Date.add(today, 1),
  Date.add(today, 2)
]

# helper: build a UTC datetime for a local-clock time on a given date
defmodule SeedHelpers do
  alias RestoBookingApp.Clock

  def at(date, hour, minute) do
    {:ok, time} = Time.new(hour, minute, 0)
    Clock.local_to_utc(date, time)
  end

  def fixtures(date, day_index) do
    # rotate the cast a bit per-day so the floor plan looks lived-in instead
    # of identical every day. base_hour stays inside the 10:00–20:00 booking
    # window so the schema's opening-hours check accepts every fixture.
    base_hour = 10 + rem(day_index, 3)

    [
      %{
        "table_id" => "T1",
        "starts_at" => at(date, base_hour, 0),
        "salutation" => "Ms",
        "first_name" => "Avery",
        "last_name" => "Chen",
        "tel" => "+1-415-555-0142",
        "email" => "avery.chen@example.com",
        "party_size" => 2,
        "special_requests" => "gluten-free menu, please"
      },
      %{
        "table_id" => "T5",
        "starts_at" => at(date, 12, 30),
        "salutation" => "Mr",
        "first_name" => "Mateo",
        "last_name" => "Romano",
        "tel" => "+1-415-555-0193",
        "email" => "mateo@example.com",
        "party_size" => 4,
        "special_requests" => "no shellfish",
        "remarks" => "anniversary dinner"
      },
      %{
        "table_id" => "T9",
        "starts_at" => at(date, 19, 0),
        "salutation" => "Ms",
        "first_name" => "Priya",
        "last_name" => "Patel",
        "tel" => "+1-415-555-0177",
        "email" => "priya.p@example.com",
        "party_size" => 6,
        "special_requests" => "vegan tasting menu"
      },
      %{
        "table_id" => "T6",
        "starts_at" => at(date, 19, 30),
        "salutation" => "Mr",
        "first_name" => "Jonas",
        "last_name" => "Becker",
        "tel" => "+49-30-555-0118",
        "email" => "jonas.becker@example.com",
        "party_size" => 3
      }
    ]
  end
end

# wipe any reservation that falls inside the seed window so re-running this
# script doesn't dogpile duplicates. we only touch dates we're about to
# re-seed — anything booked outside the four-day window is left alone.
window_start = Clock.local_to_utc(List.first(window_dates), ~T[00:00:00])
window_end = Clock.local_to_utc(Date.add(List.last(window_dates), 1), ~T[00:00:00])

deleted =
  Repo.delete_all(
    from r in Reservation,
      where: r.starts_at >= ^window_start and r.starts_at < ^window_end
  )

IO.puts("seed: cleared #{elem(deleted, 0)} existing rows in window")

window_dates
|> Enum.with_index()
|> Enum.flat_map(fn {date, idx} -> SeedHelpers.fixtures(date, idx) end)
|> Enum.each(fn attrs ->
  case Reservations.create(attrs) do
    {:ok, res} ->
      IO.puts(
        "seed: #{Date.to_iso8601(DateTime.to_date(res.starts_at))} " <>
          "#{res.table_id} #{res.first_name} #{res.last_name}"
      )

    {:error, cs} ->
      IO.puts("seed: skipped #{attrs["first_name"]} (#{inspect(cs.errors)})")
  end
end)
