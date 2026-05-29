#!/usr/bin/env bash
# one-time droplet setup for Redis. run as root from the cloned repo:
#
#   sudo bash infra/deploy/bootstrap-redis.sh /path/to/sf-voice-core
#
# or without pulling the repo first:
#
#   curl -fsSL https://raw.githubusercontent.com/sf-voice/sf-voice-core/main/infra/deploy/bootstrap-redis.sh \
#     | sudo bash -s -- --raw
#
# what it does:
#   - creates /srv/redis/data with correct ownership
#   - installs docker-compose.redis.yml at /srv/redis/docker-compose.yml
#   - brings the stack up
#
# safe to re-run: data dir is preserved between runs.
# redis runs with no auth by default because it is not exposed on a public
# port. only containers on proxy_net can reach redis:6379.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "must run as root (try: sudo bash $0 ...)" >&2
  exit 1
fi

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/sf-voice/sf-voice-core/main/infra/deploy}"
REPO_DIR="${1:-}"
CURL_ARGS=(-fsSL)

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  CURL_ARGS+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

if [[ "$REPO_DIR" == "--raw" ]]; then
  REPO_DIR=""
fi

# ── 1. dirs ──────────────────────────────────────────────────────────────
echo "==> ensuring /srv/redis/data exists"
mkdir -p /srv/redis/data
# redis:7 alpine runs as uid 999.
chown -R 999:999 /srv/redis/data
chown deploy:deploy /srv/redis

# ── 2. compose file ──────────────────────────────────────────────────────
echo "==> installing /srv/redis/docker-compose.yml"
if [[ -n "$REPO_DIR" ]]; then
  if [[ ! -d "$REPO_DIR/infra/deploy" ]]; then
    echo "no infra/deploy under $REPO_DIR — wrong path?" >&2
    exit 1
  fi

  install -m 644 -o deploy -g deploy \
    "$REPO_DIR/infra/deploy/docker-compose.redis.yml" \
    /srv/redis/docker-compose.yml
else
  tmp="$(mktemp)"
  curl "${CURL_ARGS[@]}" "$RAW_BASE/docker-compose.redis.yml" -o "$tmp"
  install -m 644 -o deploy -g deploy "$tmp" /srv/redis/docker-compose.yml
  rm -f "$tmp"
fi

# ── 3. proxy_net network (created by bootstrap.sh; ensure it exists) ─────
docker network create proxy_net 2>/dev/null || true

# ── 4. bring the stack up ────────────────────────────────────────────────
echo "==> starting redis"
docker compose -f /srv/redis/docker-compose.yml up -d

echo
echo "==> bootstrap-redis complete"
echo "    container:  redis (on proxy_net)"
echo "    data:       /srv/redis/data"
echo "    url:        redis://redis:6379 (internal proxy_net only)"
