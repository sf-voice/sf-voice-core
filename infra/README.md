# infra

operational glue — everything that runs the system but isn't application code.

## layout

- `deploy/` — droplet bootstrap, per-app deploy scripts, docker-compose
  stacks, Caddy reverse-proxy config. used by the GitHub Actions
  workflows in
  `.github/workflows/{ellie-ai,resto-booking-app,sf-voice-api,frontend,vad,caddy}.yml`
  and by one-time droplet provisioning:
  - `sudo bash infra/deploy/bootstrap.sh ...` — initial droplet bring-up
  - `sudo bash infra/deploy/bootstrap-ellie.sh ...` — ellie data dir + caddy chown
  - `sudo bash infra/deploy/bootstrap-mysql.sh ...` — mysql container + backup timer
  - `sudo bash infra/deploy/bootstrap-redis.sh ...` — redis container
  - `sudo bash infra/deploy/bootstrap-api.sh ...` — sf-voice-api data dir
  - `sudo bash infra/deploy/bootstrap-frontend.sh ...` — frontend dir
- `dev/` — local-only data layer (mysql + qdrant + redis) for
  `mise run core:dev`. see `dev/README.md`. not deployed.
- `clickhouse/` — clickhouse schemas / operator notes (placeholder).

## secrets

GitHub Actions repo secrets are the source of truth for every prod env
var. each deploy workflow re-renders the matching `.env` file on the
droplet from these secrets, so **manual edits on the droplet get wiped
on the next push**. update the GH secret and re-push to rotate.

| GH secret               | resto-demo | ellie-ai | sf-voice-api | frontend | maps to env var on droplet |
| ----------------------- | :--------: | :------: | :----------: | :------: | -------------------------- |
| `SECRET_KEY_BASE`       | ✓          | ✓        | —            | —        | `SECRET_KEY_BASE`          |
| `INTERNAL_API_TOKEN`    | ✓          | ✓        | ✓ (vad ws)   | —        | `INTERNAL_API_TOKEN`       |
| `OPENAI_API_KEY`        | —          | ✓        | —            | —        | `OPENAI_API_KEY`           |
| `TELNYX_API_KEY`        | —          | ✓        | —            | —        | `TELNYX_API_KEY`           |
| `TELNYX_PUBLIC_KEY`     | —          | ✓        | —            | —        | `TELNYX_PUBLIC_KEY`        |
| `PHONE_NUMBER`          | —          | ✓        | —            | —        | `PHONE_NUMBER`             |
| `STAFF_PHONE_E164`      | —          | ✓        | —            | —        | `STAFF_PHONE_E164`         |
| `AWS_ACCESS_KEY_ID`     | —          | ✓        | —            | —        | `AWS_ACCESS_KEY_ID`        |
| `AWS_SECRET_ACCESS_KEY` | —          | ✓        | —            | —        | `AWS_SECRET_ACCESS_KEY`    |
| `AWS_REGION`            | —          | ✓        | —            | —        | `AWS_REGION`               |
| `S3_BUCKET_NAME`        | —          | ✓        | —            | —        | `S3_BUCKET_NAME`           |
| `DATABASE_URL`          | —          | —        | ✓            | —        | `DATABASE_URL`             |
| `DROPLET_HOST`          | runner only — used to ssh to the droplet                            |
| `DROPLET_SSH_KEY`       | runner only — private key for the deploy user                       |

frontend has no `.env` at all — it's a sealed static build. the rust
api uses `INTERNAL_API_TOKEN` only as the bearer it sends when joining
ellie's VAD websocket (`/socket/vad`); ellie verifies the same token.

### what's *not* a secret (lives in compose, not `.env`)

per-app `infra/deploy/docker-compose.*.yml` carries the static stuff in
the `environment:` block:

- `PHX_HOST`, `PHX_SERVER`, `PORT` — phoenix endpoint config
- `DATABASE_PATH` — sqlite file location inside the container
- `RESTO_BASE_URL` (ellie only) — `http://resto-demo:4000` over proxy_net
- `VAD_WS_URL` (sf-voice-api only) — `ws://ellie-ai:4001/socket/vad` over proxy_net
- `REDIS_URL` (sf-voice-api only) — `redis://redis:6379` over proxy_net

### adding a new secret

1. add it as a GH repo secret.
2. extend the matching workflow's `env:` block and `envs:` list.
3. add a `printf` line to the `.env`-rendering script in that workflow.
4. add the row to the table above.

## the apps

| dir                          | runtime          | datastore                                    | container port | public host                  |
| ---------------------------- | ---------------- | -------------------------------------------- | -------------- | ---------------------------- |
| `apps/resto_booking_app/`    | elixir / phoenix | sqlite (`/data/resto.db`)                    | 4000           | `resto-demo.sf-voice.sh`     |
| `apps/ellie_ai/`             | elixir / phoenix | sqlite (`/data/ellie.db`)                    | 4001           | `ellie-ai.sf-voice.sh`       |
| `core/backend/api/`          | rust             | mysql on-prem + qdrant vectors               | 8080           | `api.sf-voice.sh`            |
| `core/frontend/`             | static (rspack)  | —                                            | 3000           | `app.sf-voice.sh`            |

Redis is deployed as a private support service on `proxy_net`. It has no
public port; the API reaches it at `redis://redis:6379`.

To install Redis on the droplet without pulling the repo first:

```bash
curl -fsSL https://raw.githubusercontent.com/sf-voice/sf-voice-core/main/infra/deploy/bootstrap-redis.sh \
  | sudo bash -s -- --raw
```

For a private raw fetch, pass the same token to the bootstrap script so it can
download the compose file too:

```bash
curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://raw.githubusercontent.com/sf-voice/sf-voice-core/main/infra/deploy/bootstrap-redis.sh \
  | sudo GITHUB_TOKEN="$GITHUB_TOKEN" bash -s -- --raw
```

If the repo is already present on the droplet:

```bash
sudo bash infra/deploy/bootstrap-redis.sh /path/to/sf-voice-core
```

caddy fronts the four public services on `*.sf-voice.sh`. cloudflare
proxies the zone with origin cert pinned in
`/etc/caddy/certs/origin.{pem,key}`.

VAD is **not a separate service.** ellie exposes a websocket at
`/socket/vad` (mounted on the same `ellie-ai:4001` container) that
consumers — the rust api today, anything else later — connect to over
`proxy_net`. auth is bearer `INTERNAL_API_TOKEN` at connect. silero
inference reuses the in-process `EllieAi.Calls.SileroVad` loaded once
per VM into `:persistent_term` from `priv/silero_vad/silero_vad.onnx`.

## not here

- application code → `apps/` (elixir) and `core/` (web / api / inference).
- secret *values* → GitHub Actions repo secrets; never commit.
- production `.env` files → written on the droplet by CI; never live in
  the repo.
