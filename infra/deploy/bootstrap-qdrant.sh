#!/usr/bin/env bash
# one-time droplet setup for Qdrant. run as root from the cloned repo:
#
#   sudo bash infra/deploy/bootstrap-qdrant.sh /path/to/sf-voice-core
#
# what it does:
#   - creates /srv/qdrant/data with correct ownership
#   - installs docker-compose.qdrant.yml at /srv/qdrant/docker-compose.yml
#   - brings the stack up
#
# safe to re-run: data dir is preserved between runs.
# qdrant runs with no auth by default — it is not exposed on a public port,
# only reachable by containers on proxy_net (api reaches it as qdrant:6334).
# add api_key to qdrant config if you expose the REST port in future.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "must run as root (try: sudo bash $0 ...)" >&2
  exit 1
fi

REPO_DIR="${1:?need path to the sf-voice-core repo as arg 1}"

if [[ ! -d "$REPO_DIR/infra/deploy" ]]; then
  echo "no infra/deploy under $REPO_DIR — wrong path?" >&2
  exit 1
fi

# ── 1. dirs ──────────────────────────────────────────────────────────────
echo "==> ensuring /srv/qdrant/data exists"
mkdir -p /srv/qdrant/data
chown -R deploy:deploy /srv/qdrant

# ── 2. compose file ──────────────────────────────────────────────────────
echo "==> installing /srv/qdrant/docker-compose.yml"
install -m 644 -o deploy -g deploy \
  "$REPO_DIR/infra/deploy/docker-compose.qdrant.yml" \
  /srv/qdrant/docker-compose.yml

# ── 3. proxy_net network (created by bootstrap.sh; ensure it exists) ─────
docker network create proxy_net 2>/dev/null || true

# ── 4. bring the stack up ────────────────────────────────────────────────
echo "==> starting qdrant"
docker compose -f /srv/qdrant/docker-compose.yml up -d

echo
echo "==> bootstrap-qdrant complete"
echo "    container:  qdrant (on proxy_net)"
echo "    data:       /srv/qdrant/data"
echo "    grpc:       qdrant:6334 (internal proxy_net only)"
echo "    http/ui:    qdrant:6333 (internal proxy_net only)"
