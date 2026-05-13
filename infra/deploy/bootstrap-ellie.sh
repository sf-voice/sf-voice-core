#!/usr/bin/env bash
# one-time droplet setup for the ellie-ai app. run as root on the droplet:
#
#   sudo bash bootstrap-ellie.sh /path/to/repo
#
# what it does:
#   - creates /srv/ellie-ai owned by the deploy user
#   - creates /srv/ellie-ai/data owned by uid 65534 (sqlite file lives here)
#   - hands /srv/caddy/ to deploy and syncs the latest Caddyfile + reload
#
# what it does NOT do anymore:
#   - write /srv/ellie-ai/.env. CI (.github/workflows/ellie-ai.yml) is the
#     source of truth for that file now — it's rewritten on every deploy
#     from the repo's GH Actions secrets.
#
# safe to re-run: every step is idempotent.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "must run as root (try: sudo bash $0 ...)" >&2
  exit 1
fi

REPO_DIR="${1:?need path to the resto-booking-app repo as arg 1}"

if [[ ! -d "$REPO_DIR/infra/deploy" ]]; then
  echo "no infra/deploy under $REPO_DIR — wrong path?" >&2
  exit 1
fi

# ── 1. app dir owned by deploy ───────────────────────────────────────────
echo "==> ensuring /srv/ellie-ai exists and is owned by deploy"
mkdir -p /srv/ellie-ai
chown deploy:deploy /srv/ellie-ai

# ── 2. sqlite data dir owned by the container user (uid 65534 / nobody) ─
echo "==> ensuring /srv/ellie-ai/data exists and is writable by the container"
mkdir -p /srv/ellie-ai/data
chown -R 65534:65534 /srv/ellie-ai/data

# ── 3. sync caddy config + hand the dir to deploy ───────────────────────
# /srv/caddy is owned by root from the original bootstrap.sh. the caddy
# workflow (.github/workflows/caddy.yml) ships future Caddyfile changes
# via scp as the deploy user, so dir + file have to be writable by deploy.
echo "==> syncing /srv/caddy/Caddyfile from repo and chowning to deploy"
install -m 644 "$REPO_DIR/infra/deploy/Caddyfile" /srv/caddy/Caddyfile
chown -R deploy:deploy /srv/caddy

if docker compose -f /srv/caddy/docker-compose.yml ps caddy >/dev/null 2>&1; then
  echo "==> reloading caddy (graceful, no downtime)"
  docker compose -f /srv/caddy/docker-compose.yml exec -T caddy \
    caddy reload --config /etc/caddy/Caddyfile
else
  echo "==> caddy stack not running — start it with: docker compose -f /srv/caddy/docker-compose.yml up -d"
fi

echo
echo "==> bootstrap-ellie complete"
echo "    next push to apps/ellie_ai writes /srv/ellie-ai/.env from GH"
echo "    secrets and brings up the container. ensure these GH repo"
echo "    secrets are populated before you push:"
echo "      SECRET_KEY_BASE  INTERNAL_API_TOKEN  OPENAI_API_KEY"
echo "      TELNYX_API_KEY   TELNYX_PUBLIC_KEY   PHONE_NUMBER"
echo "      AWS_ACCESS_KEY_ID  AWS_SECRET_ACCESS_KEY  AWS_REGION"
echo "      S3_BUCKET_NAME"
