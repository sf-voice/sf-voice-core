# infra

operational glue — everything that runs the system but isn't application code.

## layout

- `deploy/` — droplet bootstrap, per-app deploy scripts, docker-compose
  stacks, Caddy reverse-proxy config. used by the two GitHub Actions
  workflows (`.github/workflows/ellie-ai.yml`,
  `.github/workflows/resto-booking-app.yml`) and by one-time droplet
  provisioning (`sudo bash infra/deploy/bootstrap.sh ...`).
- `clickhouse/` — clickhouse schemas, migrations, and operator notes
  (placeholder; populate when we wire it up).

## not here

- application code → `apps/` (elixir) and `core/` (web / api / inference).
- secrets → `.env` at the repo root; never commit.
