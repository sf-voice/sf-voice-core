# infra/dev

local-only data layer for the `core/` stack. **not used in production**.

## what's here

- `docker-compose.yml` — mysql on `127.0.0.1`. one service. named volume
  (`sf-voice-mysql-data`) so data survives `docker compose down`.

duckdb is **not** here — it's an embedded library, not a server. the
rust api opens `./data/sf_voice.duckdb` directly. nothing to start, no
port, no healthcheck. `mise run install` creates the `data/` dir.

## the dev loop

```bash
mise run install     # one-time: deps for every stack
mise run core:dev    # data layer + frontend + backend + inference
```

`core:dev`:
1. `mkdir -p data` so duckdb's parent dir exists
2. `docker compose -f infra/dev/docker-compose.yml up -d --wait` for mysql
3. spawns `pnpm dev` (frontend, :5173, → app.sf-voice.sh in prod),
   `cargo run -p sf-voice-api` (backend, :8080, → api.sf-voice.sh in prod),
   inference placeholder, with prefixed logs
4. Ctrl+C kills the foreground processes; mysql keeps running

data-layer lifecycle (mysql container + duckdb file):
```bash
mise run db:start          # start mysql; mkdir -p data
mise run db:stop           # stop mysql, keep volume
mise run db:nuke           # stop + delete mysql volume + delete duckdb file
mise run db:logs           # tail mysql logs
```

(the elixir apps' sqlite stores are reset via `mise run sqlite:reset` —
unrelated to this dev stack.)

## defaults

| store    | location                                                            |
| -------- | ------------------------------------------------------------------- |
| mysql    | port 3306 — `sf_voice` / `sf_voice` / `sf_voice_dev` (root pw `sf_voice_root`) |
| duckdb   | `./data/sf_voice.duckdb` — open with `duckdb data/sf_voice.duckdb`  |

override mysql values by setting `MYSQL_PORT`, `MYSQL_USER`, etc. in your
root `.env` — `docker compose` reads it. override duckdb location with
`DUCKDB_PATH`.

## not here

- prod compose stacks → `infra/deploy/docker-compose.*.yml`.
- elixir apps' sqlite stores → live next to each app's `priv/`.
  unrelated to this dev stack. (the elixir side stays on sqlite per
  the project's database rule; mysql + duckdb here are for the new
  rust api only.)
