#!/usr/bin/env bash
# installed at /usr/local/bin/deploy-resto-demo.sh on the droplet.
# called by GitHub Actions over ssh on every push to main.
#
#   deploy-resto-demo.sh                  # pulls :latest
#   deploy-resto-demo.sh sha-abc1234      # rolls back / pins to a specific tag
#
# the app container runs Ecto.Migrator on boot (skip_migrations? returns false
# in releases), so just restarting it applies any new migrations atomically.

set -euo pipefail

TAG="${1:-latest}"
COMPOSE_DIR="/srv/resto-demo"

cd "$COMPOSE_DIR"

echo "==> deploying tag: $TAG"

# the image lives in a private ghcr package, so we have to authenticate before
# the pull. CI passes a short-lived GITHUB_TOKEN through the ssh session; if
# someone runs this manually they need to export GHCR_USER and GHCR_TOKEN.
if [[ -n "${GHCR_TOKEN:-}" && -n "${GHCR_USER:-}" ]]; then
  echo "==> logging in to ghcr.io as $GHCR_USER"
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
else
  echo "!! GHCR_USER / GHCR_TOKEN not set — assuming docker is already logged in" >&2
fi

# rewrite the image line in compose so `up -d` actually picks up the new tag.
# the sed pattern only touches our exact image; other lines are left alone.
sed -i.bak -E \
  "s|(image: ghcr\.io/sf-voice/restaurant-booking-app:)[^[:space:]]+|\1$TAG|" \
  docker-compose.yml

docker compose pull app
docker compose up -d --no-deps app

# clean up the .bak from sed
rm -f docker-compose.yml.bak

# trim old images so disk doesn't fill up over time
docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true

echo "==> deployed; container status:"
docker compose ps app
