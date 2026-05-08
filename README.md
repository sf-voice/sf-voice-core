# Repository layout

This repo is a [workspace](https://hex.pm/packages/workspace) with two Phoenix apps:

- **`apps/resto_booking_app`** — The Seasons booking system. The bulk of this repo. Documented below.
- **`apps/ellie_ai`** — voice AI orchestration for the booking app. End-of-turn detection via GPT realtime, inbound calls from a Telnyx phone number (with ngrok for local testing against a production number), live turn-by-turn transcripts streamed over WebSocket/SSE into the booking app's chat UI, and call audio archived to S3 for post-processing.

Workspace tooling lives at the root (`mix.exs`, `.workspace.exs`, `workspace.lock`). Each app has its own `mix.exs`, `config/`, `deps/`, and release.

---

# The Seasons Booking System

A small booking system for **The Seasons** restaurant. Single-tenant, built for guests and staff with very low technical literacy — every screen aims to be obvious without a tutorial.

The landing page is the live floor plan. There is no sign-in or marketing splash.
<img width="1500" height="973" alt="Screenshot 2026-05-04 at 1 45 54 am" src="https://github.com/user-attachments/assets/c7adcd04-b8a2-44e1-90f8-5014bc85d76a" />
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
