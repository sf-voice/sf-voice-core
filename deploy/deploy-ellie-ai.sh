#!/usr/bin/env bash
# installed at /usr/local/bin/deploy-ellie-ai.sh on the droplet.
# called by GitHub Actions over ssh on every push to main that touches ellie_ai.
#
#   deploy-ellie-ai.sh                  # pulls :latest
#   deploy-ellie-ai.sh sha-abc1234      # rolls back / pins to a specific tag

set -euo pipefail

TAG="${1:-latest}"
COMPOSE_DIR="/srv/ellie-ai"

cd "$COMPOSE_DIR"

echo "==> deploying tag: $TAG"

# log in to ghcr if CI passed credentials. for a public package this isn't
# strictly required, but doing it doesn't hurt and makes private mode a
# zero-config flip later.
if [[ -n "${GHCR_TOKEN:-}" && -n "${GHCR_USER:-}" ]]; then
  echo "==> logging in to ghcr.io as $GHCR_USER"
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
fi

# rewrite the image line in compose so `up -d` actually picks up the new tag.
sed -i.bak -E \
  "s|(image: ghcr\.io/sf-voice/ellie-ai:)[^[:space:]]+|\1$TAG|" \
  docker-compose.yml

docker compose pull app
docker compose up -d --no-deps app

rm -f docker-compose.yml.bak

# trim old images so disk doesn't fill up over time
docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true

echo "==> deployed; container status:"
docker compose ps app
