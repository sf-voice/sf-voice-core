# infra

operational glue for the droplet and local data layer.

## layout

- `deploy/compose.prod.yml` — the single production compose stack.
- `deploy/sfctl.sh` — the single production control script. installed on the
  droplet as `/srv/sf-voice/bin/sfctl`.
- `deploy/Caddyfile` — the production reverse proxy config.
- `deploy/smoke-vad.py` — deploy smoke for ellie's VAD websocket.
- `dev/` — local-only mysql + qdrant + redis for `mise run core:dev`.

production state lives under one root:

```text
/srv/sf-voice/
  bin/sfctl
  compose.prod.yml
  compose.preview.yml
  caddy/Caddyfile
  caddy/previews/*.caddy
  certs/origin.{pem,key}
  data/{mysql,mysql-backups,redis,resto,ellie}
  env/{images,api,ellie,resto,mysql,redis}.env
  previews/<preview-id>/
  state/inventory/
```

## deploy console

GitHub Actions is the normal operator surface. Use the `deploy console`
workflow for manual deploys, rollbacks, restarts, status, logs, and smoke
checks. Pushes to `main` still deploy automatically through the app workflows,
but they now call the same console workflow instead of duplicating ssh blocks.

Manual examples from the GitHub UI:

```text
operation=status service=all
operation=logs service=frontend log_lines=300
operation=smoke service=all
operation=rollback service=frontend tag=sha-<previous-sha>
```

On the droplet, the same operations are available directly:

```bash
/srv/sf-voice/bin/sfctl status all
/srv/sf-voice/bin/sfctl logs frontend 300
/srv/sf-voice/bin/sfctl smoke all
/srv/sf-voice/bin/sfctl rollback frontend sha-<previous-sha>
```

## pull request previews

Pull requests from this repo build preview images and deploy them to the same
droplet as isolated Compose projects. Fork PRs are skipped because deploy
secrets are not exposed to forked workflows.

Preview hosts use:

```text
https://preview-<pr-number>-<short-commit>.sf-voice.sh
```

The workflow comments these endpoints on the PR after a successful deploy:

```text
Frontend: https://preview-<pr-number>-<short-commit>.sf-voice.sh
API health: https://preview-<pr-number>-<short-commit>.sf-voice.sh/healthz
API base: https://preview-<pr-number>-<short-commit>.sf-voice.sh/api
```

Storage is isolated per preview:

| storage | isolation |
| --- | --- |
| mysql | one preview-local mysql container + database |
| redis | one preview-local redis container + acl file |
| qdrant cloud | one `QDRANT_COLLECTION` named from the preview id |
| clickhouse | one database named from the preview id |
| s3 | one `S3_PREFIX=preview/<preview-id>` under the shared bucket |

`sfctl preview deploy` removes older previews for the same PR before starting
the new commit preview. `sfctl preview destroy-pr <pr-number>` runs when the PR
closes and removes Compose containers, local volumes, Caddy routes, and
best-effort remote Qdrant/ClickHouse preview state.

## first migration

Do not delete old `/srv/*` paths while migrating. The safe order is:

```bash
curl -fsSL https://raw.githubusercontent.com/sf-voice/sf-voice-core/main/infra/deploy/sfctl.sh \
  | sudo bash -s -- bootstrap
sudo /srv/sf-voice/bin/sfctl inventory
sudo /srv/sf-voice/bin/sfctl migrate-layout --dry-run
sudo /srv/sf-voice/bin/sfctl migrate-layout --apply
/srv/sf-voice/bin/sfctl deploy all latest
/srv/sf-voice/bin/sfctl smoke all
sudo /srv/sf-voice/bin/sfctl cleanup --dry-run
sudo /srv/sf-voice/bin/sfctl cleanup --archive "$(date -u +%Y%m%d)"
```

`migrate-layout --apply` copies durable data and stops legacy compose stacks so
container names are free for the unified stack. It does not delete old
directories.

After 24-72h of healthy deploys and backups, delete the archive explicitly:

```bash
sudo /srv/sf-voice/bin/sfctl cleanup --delete-archive YYYYMMDD
```

`cleanup --archive` renames old paths into `/srv/.archive-YYYYMMDD/*`; it does
not remove data. `cleanup --delete-archive` is the only destructive cleanup
path.

## secrets

GitHub repo secrets are the source of truth for app runtime env. The deploy
console renders app env files on every deploy, so manual edits under
`/srv/sf-voice/env/{api,ellie,resto}.env` are overwritten.

Host-generated data-service credentials live on the VM:

- `/srv/sf-voice/env/mysql.env`
- `/srv/sf-voice/env/redis.env`
- `/srv/sf-voice/env/redis.users.acl`

When MySQL or Redis credentials are generated, copy the printed app connection
strings back to the GitHub secrets used by the API deploy.

| GH secret | used by | maps to |
| --- | --- | --- |
| `SECRET_KEY_BASE` | resto, ellie | `SECRET_KEY_BASE` |
| `INTERNAL_API_TOKEN` | resto, ellie, api | `INTERNAL_API_TOKEN` |
| `OPENAI_API_KEY` | ellie, api | `OPENAI_API_KEY` |
| `TELNYX_API_KEY` | ellie | `TELNYX_API_KEY` |
| `TELNYX_PUBLIC_KEY` | ellie | `TELNYX_PUBLIC_KEY` |
| `PHONE_NUMBER` | ellie | `PHONE_NUMBER` |
| `STAFF_PHONE_E164` | ellie | `STAFF_PHONE_E164` |
| `AWS_ACCESS_KEY_ID` | ellie, api | `AWS_ACCESS_KEY_ID` |
| `AWS_SECRET_ACCESS_KEY` | ellie, api | `AWS_SECRET_ACCESS_KEY` |
| `AWS_REGION` | ellie, api | `AWS_REGION` |
| `S3_BUCKET_NAME` | ellie, api | `S3_BUCKET_NAME` |
| `DATABASE_URL` | api | `DATABASE_URL` |
| `REDIS_URL` | api | `REDIS_URL` |
| `CLICKHOUSE_URL` | api | `CLICKHOUSE_URL` |
| `CLICKHOUSE_DATABASE` | api | `CLICKHOUSE_DATABASE` |
| `CLICKHOUSE_ACCESS_TOKEN` | api | `CLICKHOUSE_ACCESS_TOKEN` |
| `CLICKHOUSE_USER` | api | `CLICKHOUSE_USER` |
| `CLICKHOUSE_PASSWORD` | api | `CLICKHOUSE_PASSWORD` |
| `QDRANT_URL` | api | `QDRANT_URL` |
| `QDRANT_API_KEY` | api | `QDRANT_API_KEY` |
| `QDRANT_COLLECTION` | api | `QDRANT_COLLECTION` |
| `DIARIZE_URL` | api | `DIARIZE_URL` |
| `DIARIZE_API_KEY` | api | `DIARIZE_API_KEY` |
| `TWELVELABS_API_KEY` | api | `TWELVELABS_API_KEY` |
| `SF_VOICE_SECRETS_KEY` | api | `SF_VOICE_SECRETS_KEY` |
| `SF_VOICE_APP_URL` | api | `SF_VOICE_APP_URL` |
| `SF_VOICE_SKIP_AWS_VERIFY` | api | `SF_VOICE_SKIP_AWS_VERIFY` |
| `SF_VOICE_AWS_PRINCIPAL` | api | `SF_VOICE_AWS_PRINCIPAL` |
| `SF_VOICE_CFN_TEMPLATE_URL` | api | `SF_VOICE_CFN_TEMPLATE_URL` |
| `DROPLET_HOST` | runner | ssh host |
| `DROPLET_SSH_KEY` | runner | ssh key for `deploy` |

## runtime services

| service | image | data | public host |
| --- | --- | --- | --- |
| `frontend` | `ghcr.io/sf-voice/sf-voice-frontend` | none | `app.sf-voice.sh` |
| `api` | `ghcr.io/sf-voice/sf-voice-api` | mysql + redis + Qdrant Cloud | `app.sf-voice.sh/api/*` |
| `ellie-ai` | `ghcr.io/sf-voice/ellie-ai` | sqlite in `data/ellie` | `ellie-ai.sf-voice.sh` |
| `resto-demo` | `ghcr.io/sf-voice/restaurant-booking-app` | sqlite in `data/resto` | `resto-demo.sf-voice.sh` |
| `mysql` | `mysql:8.4` | `data/mysql` | private docker network, loopback `3306` |
| `redis` | `redis:7.4-alpine` | `data/redis` | private docker network |
| `caddy` | `caddy:2-alpine` | caddy volumes + certs | public `80/443` |

The frontend image writes `/version.json` at build time. `sfctl status
frontend` compares that public version with the running Docker image label so
we can prove the VM is serving the expected SHA.
