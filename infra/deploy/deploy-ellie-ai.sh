#!/usr/bin/env bash
# installed at /srv/ellie-ai/deploy-ellie-ai.sh on the droplet.
# called by GitHub Actions over ssh on every push to main that touches ellie_ai.
#
#   deploy-ellie-ai.sh                  # pulls :latest
#   deploy-ellie-ai.sh sha-abc1234      # rolls back / pins to a specific tag
#
# DB strategy for the demo: wipe sqlite on every deploy, re-migrate on
# boot (via the Ecto.Migrator child in EllieAi.Application), then re-
# seed the demo orgs via Release.seed(). that means every push gives
# the demo a clean db with the canonical seasons-* orgs and no stale
# call/transcript data.
#
# this is intentional for the demo and would be wrong in a real-prod
# context — change this script when ellie holds data anyone cares
# about across deploys.

set -euo pipefail

TAG="${1:-latest}"
COMPOSE_DIR="/srv/ellie-ai"

cd "$COMPOSE_DIR"

echo "==> deploying tag: $TAG"

if [[ -n "${GHCR_TOKEN:-}" && -n "${GHCR_USER:-}" ]]; then
  echo "==> logging in to ghcr.io as $GHCR_USER"
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
fi

# rewrite the image line in compose so `up -d` actually picks up the new tag.
sed -i.bak -E \
  "s|(image: ghcr\.io/sf-voice/ellie-ai:)[^[:space:]]+|\1$TAG|" \
  docker-compose.yml
rm -f docker-compose.yml.bak

# stop the container before wiping the sqlite file so we don't fight
# an open file handle. `down` removes the container entirely; `up -d`
# below recreates it cleanly with the new image.
echo "==> stopping ellie container (if running) before db wipe"
docker compose down --remove-orphans 2>/dev/null || true

echo "==> wiping sqlite db at ./data/ellie.db (+ wal/shm sidecars)"
rm -f ./data/ellie.db ./data/ellie.db-wal ./data/ellie.db-shm

# pull + bring up. on boot, the Ecto.Migrator child in
# EllieAi.Application runs all pending migrations against the fresh
# sqlite file before Reconciliation / the endpoint start querying.
docker compose pull app
docker compose up -d --no-deps app

# wait for the release to be fully started before we eval into it.
# rpc returns successfully once the IEx-style remote shell is reachable.
echo "==> waiting for app to be ready before seeding"
for i in $(seq 1 60); do
  if docker compose exec -T app /app/bin/ellie_ai rpc "IO.puts(:up)" >/dev/null 2>&1; then
    break
  fi
  if [ "$i" = "60" ]; then
    echo "!! app didn't come up in 60s — check `docker compose logs app`" >&2
    exit 1
  fi
  sleep 1
done

echo "==> running release seed task"
docker compose exec -T app /app/bin/ellie_ai eval "EllieAi.Release.seed()" || \
  echo "!! seed task failed — orgs may be missing until next deploy" >&2

# trim old images so disk doesn't fill up over time.
docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true

echo "==> deployed; container status:"
docker compose ps app
