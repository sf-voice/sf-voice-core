# multi-org seed: builds two demo restaurants under one resto deploy,
# each with their own floor plan, menu, and a rolling four-day window
# of fixture reservations. safe to run repeatedly: orgs/tables/menu use
# upsert-by-slug; reservations are wiped within the seed window before
# re-insert.

import Ecto.Query

alias RestoBookingApp.{Bookings, Clock, Menu, Orgs, Repo, Tables}
alias RestoBookingApp.Reservations.Reservation

# ── orgs ───────────────────────────────────────────────────────────────────

orgs_spec = [
  %{
    slug: "seasons-sf",
    name: "The Seasons",
    location: "San Francisco, CA",
    time_zone: "America/Los_Angeles"
  },
  %{
    slug: "seasons-la",
    name: "The Seasons",
    location: "Los Angeles, CA",
    time_zone: "America/Los_Angeles"
  },
  %{
    slug: "seasons-ny",
    name: "The Seasons",
    location: "New York, NY",
    time_zone: "America/New_York"
  }
]

orgs =
  Enum.map(orgs_spec, fn spec ->
    {:ok, org} = Orgs.upsert_by_slug(spec.slug, spec)
    IO.puts("seed: org #{org.slug} (#{org.location})")
    org
  end)

# ── tables: same nine-table layout in both orgs (the seasons brand) ────────

tables_spec = [
  %{slug: "T1", seats: 2, shape: "round", x: 0, y: 0, sort_order: 1},
  %{slug: "T2", seats: 2, shape: "round", x: 1, y: 0, sort_order: 2},
  %{slug: "T3", seats: 2, shape: "round", x: 2, y: 0, sort_order: 3},
  %{slug: "T4", seats: 2, shape: "round", x: 3, y: 0, sort_order: 4},
  %{slug: "T5", seats: 4, shape: "square", x: 0, y: 1, sort_order: 5},
  %{slug: "T6", seats: 4, shape: "square", x: 1, y: 1, sort_order: 6},
  %{slug: "T7", seats: 4, shape: "square", x: 2, y: 1, sort_order: 7},
  %{slug: "T8", seats: 4, shape: "square", x: 3, y: 1, sort_order: 8},
  %{slug: "T9", seats: 6, shape: "rect", x: 0, y: 2, sort_order: 9}
]

Enum.each(orgs, fn org ->
  Enum.each(tables_spec, fn t ->
    {:ok, _} = Tables.upsert(org.id, t)
  end)

  IO.puts("seed: #{length(tables_spec)} tables for #{org.slug}")
end)

# ── menu: same three services + items in both orgs ─────────────────────────

menu_spec = [
  # breakfast
  %{
    service: "breakfast",
    name: "Sourdough Toast & Jam",
    price_cents: 700,
    dietary: [:vegan],
    sort_order: 1
  },
  %{
    service: "breakfast",
    name: "Garden Veg Shakshuka",
    price_cents: 1400,
    dietary: [:vegetarian, :gluten_free],
    sort_order: 2
  },
  %{
    service: "breakfast",
    name: "Smoked Salmon Bagel",
    price_cents: 1600,
    dietary: [:nut_free],
    sort_order: 3
  },
  %{
    service: "breakfast",
    name: "Buckwheat Pancakes",
    price_cents: 1200,
    dietary: [:vegetarian, :nut_free],
    sort_order: 4
  },
  %{
    service: "breakfast",
    name: "Oat Porridge, Berries",
    price_cents: 900,
    dietary: [:vegan, :gluten_free],
    sort_order: 5
  },

  # lunch
  %{
    service: "lunch",
    name: "House Caesar Salad",
    price_cents: 1500,
    dietary: [:vegetarian],
    sort_order: 1
  },
  %{
    service: "lunch",
    name: "Roasted Squash Risotto",
    price_cents: 1800,
    dietary: [:vegetarian, :gluten_free],
    sort_order: 2
  },
  %{
    service: "lunch",
    name: "Steak Frites",
    price_cents: 2600,
    dietary: [:gluten_free],
    sort_order: 3
  },
  %{
    service: "lunch",
    name: "Crispy Tofu Bowl",
    price_cents: 1700,
    dietary: [:vegan, :gluten_free, :nut_free],
    sort_order: 4
  },
  %{
    service: "lunch",
    name: "Mushroom Tagliatelle",
    price_cents: 1900,
    dietary: [:vegetarian],
    sort_order: 5
  },

  # dinner
  %{
    service: "dinner",
    name: "Charred Octopus",
    price_cents: 2400,
    dietary: [:gluten_free, :dairy_free],
    sort_order: 1
  },
  %{
    service: "dinner",
    name: "Wagyu Tartare",
    price_cents: 2900,
    dietary: [:gluten_free, :nut_free],
    sort_order: 2
  },
  %{
    service: "dinner",
    name: "Truffle Tagliolini",
    price_cents: 3200,
    dietary: [:vegetarian],
    sort_order: 3
  },
  %{
    service: "dinner",
    name: "Branzino al Sale",
    price_cents: 3600,
    dietary: [:gluten_free, :dairy_free],
    sort_order: 4
  },
  %{
    service: "dinner",
    name: "Beetroot Wellington",
    price_cents: 2800,
    dietary: [:vegan],
    sort_order: 5
  },
  %{
    service: "dinner",
    name: "Dark Chocolate Tart",
    price_cents: 1100,
    dietary: [:vegetarian, :gluten_free],
    sort_order: 6
  }
]

Enum.each(orgs, fn org ->
  Enum.each(menu_spec, fn item ->
    {:ok, _} = Menu.upsert(org.id, item)
  end)

  IO.puts("seed: #{length(menu_spec)} menu items for #{org.slug}")
end)

# ── reservations: rolling four-day window per org ──────────────────────────

today = Clock.today()
window_dates = [Date.add(today, -1), today, Date.add(today, 1), Date.add(today, 2)]

window_start = Clock.local_to_utc(List.first(window_dates), ~T[00:00:00])
window_end = Clock.local_to_utc(Date.add(List.last(window_dates), 1), ~T[00:00:00])

defmodule SeedHelpers do
  alias RestoBookingApp.Clock

  def at(date, hour, minute) do
    {:ok, time} = Time.new(hour, minute, 0)
    Clock.local_to_utc(date, time)
  end

  # rotate cast per-day so the floor plan looks lived-in. one fixture set
  # per org with slightly different names so demos can tell them apart.
  def fixtures(date, day_index, :seasons_sf) do
    base_hour = 10 + rem(day_index, 3)

    [
      %{
        "table_id" => "T1",
        "starts_at" => at(date, base_hour, 0),
        "salutation" => "Ms",
        "first_name" => "Avery",
        "last_name" => "Chen",
        "phone" => "+14155550142",
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
        "phone" => "+14155550193",
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
        "phone" => "+14155550177",
        "email" => "priya.p@example.com",
        "party_size" => 6,
        "special_requests" => "vegan tasting menu"
      }
    ]
  end

  def fixtures(date, day_index, :seasons_la) do
    base_hour = 11 + rem(day_index, 3)

    [
      %{
        "table_id" => "T2",
        "starts_at" => at(date, base_hour, 0),
        "salutation" => "Mr",
        "first_name" => "Diego",
        "last_name" => "Vargas",
        "phone" => "+13235550112",
        "email" => "diego@example.com",
        "party_size" => 2,
        "special_requests" => "window seat please"
      },
      %{
        "table_id" => "T7",
        "starts_at" => at(date, 18, 30),
        "salutation" => "Ms",
        "first_name" => "Hana",
        "last_name" => "Watanabe",
        "phone" => "+13235550168",
        "email" => "hana.w@example.com",
        "party_size" => 4,
        "remarks" => "celebrating new job"
      }
    ]
  end

  def fixtures(date, day_index, :seasons_ny) do
    base_hour = 12 + rem(day_index, 3)

    [
      %{
        "table_id" => "T3",
        "starts_at" => at(date, base_hour, 0),
        "salutation" => "Mr",
        "first_name" => "Sam",
        "last_name" => "Okafor",
        "phone" => "+12125550155",
        "email" => "sam.okafor@example.com",
        "party_size" => 2,
        "special_requests" => "quiet corner if possible"
      },
      %{
        "table_id" => "T6",
        "starts_at" => at(date, 19, 30),
        "salutation" => "Ms",
        "first_name" => "Eleanor",
        "last_name" => "Park",
        "phone" => "+12125550188",
        "email" => "eleanor.park@example.com",
        "party_size" => 4,
        "remarks" => "out-of-town guests"
      }
    ]
  end
end

deleted =
  Repo.delete_all(
    from r in Reservation,
      where: r.starts_at >= ^window_start and r.starts_at < ^window_end
  )

IO.puts("seed: cleared #{elem(deleted, 0)} reservation rows in window")

org_keys = %{
  "seasons-sf" => :seasons_sf,
  "seasons-la" => :seasons_la,
  "seasons-ny" => :seasons_ny
}

Enum.each(orgs, fn org ->
  key = Map.fetch!(org_keys, org.slug)

  window_dates
  |> Enum.with_index()
  |> Enum.flat_map(fn {date, idx} -> SeedHelpers.fixtures(date, idx, key) end)
  |> Enum.each(fn attrs ->
    case Bookings.book(org.id, attrs) do
      {:ok, res} ->
        IO.puts(
          "seed: #{org.slug} #{Date.to_iso8601(DateTime.to_date(res.starts_at))} " <>
            "#{res.table_id} #{res.customer.first_name} #{res.customer.last_name}"
        )

      {:error, cs} ->
        IO.puts("seed: #{org.slug} skipped #{attrs["first_name"]} (#{inspect(cs.errors)})")
    end
  end)
end)
