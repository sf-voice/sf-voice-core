#!/usr/bin/env bash
# one-time droplet setup for the ellie-ai app. run as root on the droplet:
#
#   sudo bash bootstrap-ellie.sh /path/to/repo
#
# what it does:
#   - creates /srv/ellie-ai owned by the deploy user
#   - generates a phoenix SECRET_KEY_BASE and writes /srv/ellie-ai/.env
#   - syncs the latest Caddyfile from the repo and restarts caddy so
#     ellie-ai.sf-voice.sh starts routing.
#
# safe to re-run: it skips .env if it already exists (so we don't blow away
# an active SECRET_KEY_BASE and invalidate sessions).

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

# ── 2. .env with SECRET_KEY_BASE ─────────────────────────────────────────
if [[ -f /srv/ellie-ai/.env ]]; then
  echo "==> /srv/ellie-ai/.env already exists — leaving it alone"
else
  echo "==> generating SECRET_KEY_BASE and writing /srv/ellie-ai/.env"
  secret="$(openssl rand -base64 64 | tr -d '\n=' | head -c 64)"
  cat > /srv/ellie-ai/.env <<EOF
SECRET_KEY_BASE=$secret
EOF
  chown deploy:deploy /srv/ellie-ai/.env
  chmod 600 /srv/ellie-ai/.env
fi

# ── 3. sync caddy config + restart ───────────────────────────────────────
echo "==> syncing /srv/caddy/Caddyfile from repo"
install -m 644 "$REPO_DIR/infra/deploy/Caddyfile" /srv/caddy/Caddyfile

if docker compose -f /srv/caddy/docker-compose.yml ps caddy >/dev/null 2>&1; then
  echo "==> restarting caddy"
  docker compose -f /srv/caddy/docker-compose.yml restart caddy
else
  echo "==> caddy stack not running — start it with: docker compose -f /srv/caddy/docker-compose.yml up -d"
fi

echo
echo "==> bootstrap-ellie complete"
echo "    next push to apps/ellie_ai will scp the deploy script + compose"
echo "    and run it as the deploy user. no more /usr/local/bin gymnastics."
