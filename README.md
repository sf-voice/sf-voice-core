# The Seasons Booking System

A small booking system for **The Seasons** restaurant. Single-tenant, built for guests and staff with very low technical literacy — every screen aims to be obvious without a tutorial.

The landing page is the live floor plan. There is no sign-in or marketing splash.

## Stack

- **Elixir** + **Phoenix 1.8** (LiveView)
- **SQLite** via `ecto_sqlite3`
- **Bandit** HTTP server
- Hosted on **Digital Ocean** (San Francisco)

## Quick start

Requires Elixir 1.15+ and Erlang/OTP installed.

```sh
mix setup       # installs deps, creates DB, runs migrations, seeds, builds assets
mix phx.server  # serves on http://localhost:4000
```

Or inside IEx: `iex -S mix phx.server`.

## Migrations

`mix setup` already runs migrations on first-time install. You only need the commands below when you add or change a migration.

### Development

```sh
mix ecto.gen.migration <name>   # scaffold a new migration
mix ecto.migrate                # apply pending migrations
mix ecto.rollback               # roll back the last migration
mix ecto.reset                  # drop, recreate, migrate, seed (destroys local data)
```

### Production (release)

The release ships a small wrapper script and a release task. Either works:

```sh
# from inside the release
bin/resto_booking_app eval "RestoBookingApp.Release.migrate()"

# or use the bundled overlay script
bin/migrate
```

To roll back a specific migration in prod:

```sh
bin/resto_booking_app eval "RestoBookingApp.Release.rollback(RestoBookingApp.Repo, <version>)"
```

## Time matters (read this before demoing)

The restaurant runs in **Pacific time** (`America/Los_Angeles`). All human-facing date/time logic — the floor plan's day, opening-hour validation (06:00–20:00 last start), the slot grid — is interpreted in that zone. Storage is UTC; conversion happens at the boundary.

Everything goes through `RestoBookingApp.Clock`. If you change the timezone, change it once in `config/config.exs` (`:resto_booking_app, :timezone`) — don't sprinkle zones around.

For the demo this means: a booking at "19:00" is 19:00 PT, regardless of the server's locale or what time it is in UTC. If the floor plan looks wrong around midnight UTC (which is mid-afternoon PT), check that the `tz` dep is actually loaded (`mix deps.get`) and that `Tz.TimeZoneDatabase` is the configured database.

## API

JSON endpoints live under `/api`: `menu`, `tables`, `availability`, and `reservations` (full CRUD). The HTML floor plan is at `/`.
