#!/usr/bin/env bash
# preview teardown only. core preview deploys moved to sf-voice/core.
# this file stays so `sfctl preview destroy-pr` can clean up existing
# previews on the droplet.

preview() {
  local action="${1:-}"
  shift || true
  case "$action" in
    destroy) preview_destroy "$@" ;;
    destroy-pr) preview_destroy_pr "$@" ;;
    status) preview_status "${1:-}" ;;
    logs) preview_logs "${1:-}" "${2:-$DEFAULT_LOG_LINES}" ;;
    *) die "preview deploy moved to sf-voice/core; this sfctl only supports destroy/status/logs" ;;
  esac
}

preview_root() {
  local preview_id="$1"
  printf '%s/previews/%s' "$ROOT" "$preview_id"
}

preview_compose() {
  local preview_id="$1"
  shift || true
  local root
  root="$(preview_root "$preview_id")"
  docker compose \
    --env-file "$root/env/images.env" \
    --env-file "$root/env/preview.env" \
    -f "$root/compose.preview.yml" "$@"
}

preview_validate_id() {
  local preview_id="$1"
  [[ "$preview_id" =~ ^pr-[0-9]+$ ]] \
    || die "preview id must look like pr-123"
}

preview_clickhouse_query() {
  local query="$1"
  local auth_args=()
  if [[ -n "${CLICKHOUSE_ACCESS_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer $CLICKHOUSE_ACCESS_TOKEN")
  elif [[ -n "${CLICKHOUSE_USER:-}" && -n "${CLICKHOUSE_PASSWORD:-}" ]]; then
    auth_args=(-H "X-ClickHouse-User: $CLICKHOUSE_USER" -H "X-ClickHouse-Key: $CLICKHOUSE_PASSWORD")
  fi

  curl -fsS "${auth_args[@]}" \
    --data-binary "$query" \
    "$CLICKHOUSE_URL/" >/dev/null
}

preview_destroy() {
  local preview_id="${1:-}"
  [[ -n "$preview_id" ]] || die "usage: sfctl preview destroy <preview-id>"
  preview_validate_id "$preview_id"

  local root
  root="$(preview_root "$preview_id")"
  if [[ -d "$root" ]]; then
    preview_cleanup_remote_storage "$preview_id" || true
    preview_compose "$preview_id" down -v --remove-orphans || true
  fi
  rm -f "$ROOT/caddy/previews/$preview_id.caddy"
  docker run --rm -v "$ROOT/previews:/p" alpine:3 \
    sh -c "rm -rf /p/$preview_id" \
    || rm -rf "$root"
  reload_caddy
  echo "sfctl: preview destroyed: $preview_id"
}

preview_destroy_pr() {
  local pr_number="${1:-}"
  [[ "$pr_number" =~ ^[0-9]+$ ]] || die "preview pr number must be numeric"
  local candidate candidate_id glob
  for glob in "$ROOT/previews/pr-$pr_number" "$ROOT/previews/preview-$pr_number-"*; do
    for candidate in $glob; do
      [[ -d "$candidate" ]] || continue
      candidate_id="$(basename "$candidate")"
      preview_cleanup_remote_storage "$candidate_id" || true
      preview_compose "$candidate_id" down -v --remove-orphans || true
      rm -f "$ROOT/caddy/previews/$candidate_id.caddy"
      docker run --rm -v "$ROOT/previews:/p" alpine:3 \
        sh -c "rm -rf /p/$candidate_id" \
        || rm -rf "$candidate"
    done
  done
  reload_caddy
  echo "sfctl: previews destroyed for PR #$pr_number"
}

preview_cleanup_remote_storage() {
  local preview_id="$1"
  local root collection database
  root="$(preview_root "$preview_id")"
  collection="$(read_env_value "$root/env/api.env" QDRANT_COLLECTION)"
  database="$(read_env_value "$root/env/api.env" CLICKHOUSE_DATABASE)"

  if [[ -n "$database" && -n "${CLICKHOUSE_URL:-}" ]]; then
    preview_clickhouse_query "DROP DATABASE IF EXISTS \`$database\`" || true
  fi

  if [[ -n "$collection" && -n "${QDRANT_API_KEY:-}" && ( -n "${QDRANT_URL:-}" || -n "${QDRANT_REST_URL:-}" ) ]]; then
    local rest_url
    rest_url="$(preview_qdrant_rest_url)"
    curl -fsS -X DELETE \
      -H "api-key: $QDRANT_API_KEY" \
      "$rest_url/collections/$collection" >/dev/null || true
  fi
}

preview_qdrant_rest_url() {
  local url="${QDRANT_REST_URL:-${QDRANT_URL:-}}"
  url="${url%/}"
  if [[ -z "${QDRANT_REST_URL:-}" ]]; then
    url="${url/:6334/:6333}"
  fi
  printf '%s' "$url"
}

preview_status() {
  local preview_id="${1:-}"
  [[ -n "$preview_id" ]] || die "usage: sfctl preview status <preview-id>"
  preview_validate_id "$preview_id"
  preview_compose "$preview_id" ps
}

preview_logs() {
  local preview_id="${1:-}"
  local lines="${2:-$DEFAULT_LOG_LINES}"
  [[ -n "$preview_id" ]] || die "usage: sfctl preview logs <preview-id> [lines]"
  preview_validate_id "$preview_id"
  for service in frontend api mysql redis; do
    echo "--- $preview_id-$service ---"
    docker logs --tail "$lines" "$preview_id-$service" 2>&1 || true
  done
}

reload_caddy() {
  if docker ps --format '{{.Names}}' | grep -qx caddy; then
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile
  fi
}
