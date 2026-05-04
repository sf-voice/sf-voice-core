# a few demo bookings on today's floor plan so the landing page isn't empty
# on first boot. safe to run multiple times — duplicates are filtered out
# by the overlap rule and just return :error, which we ignore here.

alias RestoBookingApp.Reservations

today = Date.utc_today()

defmodule SeedHelpers do
  def at(date, hour, minute) do
    {:ok, time} = Time.new(hour, minute, 0)
    {:ok, dt} = DateTime.new(date, time, "Etc/UTC")
    dt
  end
end

bookings = [
  %{
    table_id: "T1",
    starts_at: SeedHelpers.at(today, 8, 0),
    name: "Avery Chen",
    party_size: 2,
    dietary: "gluten free"
  },
  %{
    table_id: "T5",
    starts_at: SeedHelpers.at(today, 12, 30),
    name: "Mateo Romano",
    party_size: 4,
    dietary: "no shellfish"
  },
  %{
    table_id: "T9",
    starts_at: SeedHelpers.at(today, 19, 0),
    name: "Priya Patel",
    party_size: 6,
    dietary: "vegan"
  },
  %{
    table_id: "T6",
    starts_at: SeedHelpers.at(today, 19, 30),
    name: "Jonas Becker",
    party_size: 3,
    dietary: nil
  }
]

for attrs <- bookings do
  case Reservations.create(attrs) do
    {:ok, res} ->
      IO.puts("seeded reservation #{res.id} for #{res.name} @ #{res.table_id}")

    {:error, _} ->
      IO.puts("skipped (already exists or invalid): #{attrs.name} @ #{attrs.table_id}")
  end
end
