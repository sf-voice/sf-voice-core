# Repository layout

This repo is a monorepo housing two related products:

- **The Seasons booking system** — Example application. Single-tenant restaurant booking app. Elixir/Phoenix. Lives under `apps/resto_booking_app` (the integration service) and `apps/ellie_ai` (a zero-franework voice AI app).
- **Core** — Core platform. Rust API (Control Plane) + C++ DBMS (Data Plane) + React frontend. Lives under `core/`.


```
apps/
  resto_booking_app/   ─ Phoenix booking app for The Seasons
  ellie_ai/            ─ voice AI orchestration for the booking app written in elixir
core/
  backend/api/         ─ Rust + Axum API 
  frontend/            ─ React + rspack + Tailwind frontend
  plane/               ─ C++ for data plane management on customer's infra
  inference/           ─ Python for hosted inference 
infra/
  dev/                 ─ docker-compose for local MySQL
  deploy/              ─ prod compose files, Caddyfile, bootstrap scripts
elixir/, rust/         ─ reserved for extracted library crates
docs/                  ─ misc operational notes (telnyx setup, etc)
mise.toml              ─ tool versions + tasks for every stack in here
.env                   ─ single source of truth for every var, every app
```

Workspace tooling lives at the root: `mix.exs` + `.workspace.exs` + `workspace.lock` for the Elixir apps; `Cargo.toml` (workspace) for the Rust crates; `pnpm-workspace.yaml` for the JS side. Each app/package has its own manifest underneath.

## Tooling — `mise`

[`mise`](https://mise.jdx.dev) pins Erlang, Elixir, Node, C++, pnpm, Rust, and the DuckDB CLI to the versions CI uses, and exposes every dev task. After `mise install` from this directory:

```sh
mise tasks                  # list everything available
mise run install            # one-time bootstrap across all stacks
mise run dev                # full Elixir stack: ngrok + both Phoenix apps
mise run core:dev           # full sf-voice stack: mysql + backend + frontend
mise run test               # workspace test runner
```

`mise` also auto-loads `.env` on `cd` into the repo, so every shell and every task starts from the same env without sourcing anything by hand.

---

## Quick start

Requires the `mise` tools above plus Docker.

```sh
mise run install   # one-time: deps for every stack, including Rust + pnpm
mise run core:dev  # boots MySQL via docker-compose, then frontend + backend
```

That opens:
- **Frontend** on http://localhost:3000 — landing on the public light-theme shell. 

- **Backend API** on http://localhost:8080 — `GET /healthz` for liveness, `GET /api/hello` for a sanity check.


Dev escape hatch: `SF_VOICE_SKIP_AWS_VERIFY=1` lets you click through the bucket-connect flow without provisioning anything in AWS.

## Production

The deploy story for sf-voice lives in `infra/deploy/`:

- `docker-compose.api.yml`, `docker-compose.frontend.yml`, `docker-compose.mysql.yml` — one compose file per service so each can be redeployed independently.
- `bootstrap-*.sh` — first-boot provisioning for each service on a fresh DO droplet.
- `Caddyfile` — TLS-terminating edge proxy for `api.sf-voice.sh` and `app.sf-voice.sh`.
- `mysql-backup.sh` — nightly logical dump.

Each service's GitHub Actions workflow lives under `.github/workflows/` (`frontend.yml`, `sf-voice-api.yml`, `caddy.yml`, etc).
