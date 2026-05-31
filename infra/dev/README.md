# infra/dev

local-only data layer for the `core/` stack. **not used in production**.

## what's here

- `docker-compose.yml` — mysql, qdrant, and redis on `127.0.0.1`.
  named volumes keep data across `docker compose down`.

## the dev loop

```bash
mise run install     # one-time: deps for every stack
mise run core:dev    # data layer + frontend + backend + inference
```

`core:dev`:
1. `docker compose -f infra/dev/docker-compose.yml up -d --wait` for mysql,
   qdrant, and redis
2. spawns `pnpm dev` (frontend, :5173, → app.sf-voice.sh in prod),
   `cargo run -p sf-voice-api` (backend, :8080, → api.sf-voice.sh in prod),
   inference placeholder, with prefixed logs
3. Ctrl+C kills the foreground processes; mysql keeps running

data-layer lifecycle:
```bash
mise run db:start          # start dev data layer
mise run db:stop           # stop dev data layer, keep volumes
mise run db:nuke           # stop + delete volumes
mise run db:logs           # tail data-layer logs
```

(the elixir apps' sqlite stores are reset via `mise run sqlite:reset` —
unrelated to this dev stack.)

## defaults

| store    | location                                                            |
| -------- | ------------------------------------------------------------------- |
| mysql    | port 3306 — `sf_voice` / `sf_voice` / `sf_voice_dev` (root pw `sf_voice_root`) |
| qdrant   | ports 6333 REST / 6334 gRPC — `http://127.0.0.1:6333`             |
| redis    | port 6379 — `redis://127.0.0.1:6379`                              |

override mysql values by setting `MYSQL_PORT`, `MYSQL_USER`, etc. in your
root `.env` — `docker compose` reads it. override redis port with
`REDIS_PORT`.

## not here

- prod compose stack → `infra/deploy/compose.prod.yml`.
- elixir apps' sqlite stores → live next to each app's `priv/`.
  unrelated to this dev stack.
