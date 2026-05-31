#!/usr/bin/env bash

COMPOSE_FILE="$ROOT/compose.prod.yml"
ENV_DIR="$ROOT/env"
DATA_DIR="$ROOT/data"
STATE_DIR="$ROOT/state"
BIN_DIR="$ROOT/bin"
DEFAULT_LOG_LINES=200

OLD_DIRS=(
  /srv/frontend
  /srv/sf-voice-api
  /srv/resto-demo
  /srv/ellie-ai
  /srv/mysql
  /srv/qdrant
  /srv/redis
  /srv/caddy
)

usage() {
  cat <<'EOF'
usage:
  sfctl bootstrap
  sfctl inventory
  sfctl migrate-layout --dry-run
  sfctl migrate-layout --apply
  sfctl deploy <frontend|api|ellie|resto|caddy|mysql|qdrant|redis|all> <tag>
  sfctl rollback <frontend|api|ellie|resto> <tag>
  sfctl restart <service|all>
  sfctl status [service|all]
  sfctl logs <service> [lines]
  sfctl smoke [service|all]
  sfctl cleanup --dry-run
  sfctl cleanup --archive [YYYYMMDD]
  sfctl cleanup --delete-archive YYYYMMDD
EOF
}

die() {
  echo "sfctl: $*" >&2
  exit 1
}

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "this command must run as root"
}

compose() {
  ensure_images_env
  docker compose --env-file "$ENV_DIR/images.env" -f "$COMPOSE_FILE" "$@"
}

service_name() {
  case "${1:-}" in
    frontend) echo "frontend" ;;
    api) echo "api" ;;
    ellie) echo "ellie-ai" ;;
    resto) echo "resto-demo" ;;
    caddy) echo "caddy" ;;
    mysql) echo "mysql" ;;
    qdrant) echo "qdrant" ;;
    redis) echo "redis" ;;
    all) echo "all" ;;
    *) die "unknown service: ${1:-<empty>}" ;;
  esac
}

image_var() {
  case "$1" in
    frontend) echo "FRONTEND_IMAGE_TAG" ;;
    api) echo "API_IMAGE_TAG" ;;
    ellie) echo "ELLIE_IMAGE_TAG" ;;
    resto) echo "RESTO_IMAGE_TAG" ;;
    *) die "$1 does not have an image tag" ;;
  esac
}

image_ref() {
  case "$1" in
    frontend) echo "ghcr.io/sf-voice/sf-voice-frontend" ;;
    api) echo "ghcr.io/sf-voice/sf-voice-api" ;;
    ellie) echo "ghcr.io/sf-voice/ellie-ai" ;;
    resto) echo "ghcr.io/sf-voice/restaurant-booking-app" ;;
    *) die "$1 does not have an image" ;;
  esac
}

containers_for() {
  case "${1:-all}" in
    frontend) echo frontend ;;
    api) echo api ;;
    ellie) echo ellie-ai ;;
    resto) echo resto-demo ;;
    caddy) echo caddy ;;
    mysql) echo mysql ;;
    qdrant) echo qdrant ;;
    redis) echo redis ;;
    all) echo caddy frontend api ellie-ai resto-demo mysql qdrant redis ;;
    *) die "unknown service: $1" ;;
  esac
}

ensure_dirs() {
  mkdir -p \
    "$BIN_DIR" \
    "$ENV_DIR" \
    "$STATE_DIR/inventory" \
    "$ROOT/caddy" \
    "$ROOT/certs" \
    "$DATA_DIR/mysql" \
    "$DATA_DIR/mysql-backups" \
    "$DATA_DIR/qdrant" \
    "$DATA_DIR/redis" \
    "$DATA_DIR/resto" \
    "$DATA_DIR/ellie"
}

ensure_images_env() {
  mkdir -p "$ENV_DIR"
  if [[ ! -f "$ENV_DIR/images.env" ]]; then
    cat > "$ENV_DIR/images.env" <<'EOF'
FRONTEND_IMAGE_TAG=latest
API_IMAGE_TAG=latest
ELLIE_IMAGE_TAG=latest
RESTO_IMAGE_TAG=latest
EOF
  fi
}

set_image_tag() {
  local service="$1"
  local tag="$2"
  local var tmp
  var="$(image_var "$service")"
  tmp="$(mktemp)"
  ensure_images_env
  awk -F= -v key="$var" -v value="$tag" '
    BEGIN { found = 0 }
    $1 == key { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$ENV_DIR/images.env" > "$tmp"
  install -m 600 "$tmp" "$ENV_DIR/images.env"
  rm -f "$tmp"
}

write_env_file() {
  local path="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  umask 077
  for name in "$@"; do
    if [[ -n "${!name:-}" ]]; then
      printf '%s=%s\n' "$name" "${!name}" >> "$tmp"
    fi
  done
  install -m 600 "$tmp" "$path"
  rm -f "$tmp"
}

write_service_env() {
  local service="$1"
  mkdir -p "$ENV_DIR"
  case "$service" in
    api)
      write_env_file "$ENV_DIR/api.env" \
        DATABASE_URL REDIS_URL INTERNAL_API_TOKEN OPENAI_API_KEY \
        CLICKHOUSE_URL CLICKHOUSE_DATABASE CLICKHOUSE_ACCESS_TOKEN \
        CLICKHOUSE_USER CLICKHOUSE_PASSWORD QDRANT_API_KEY \
        QDRANT_COLLECTION DIARIZE_URL DIARIZE_API_KEY \
        AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION S3_BUCKET_NAME \
        TWELVELABS_API_KEY SF_VOICE_SECRETS_KEY SF_VOICE_APP_URL \
        SF_VOICE_SKIP_AWS_VERIFY COOKIE_SECURE \
        SF_VOICE_AWS_PRINCIPAL SF_VOICE_CFN_TEMPLATE_URL
      ;;
    ellie)
      write_env_file "$ENV_DIR/ellie.env" \
        SECRET_KEY_BASE INTERNAL_API_TOKEN OPENAI_API_KEY TELNYX_API_KEY \
        TELNYX_PUBLIC_KEY PHONE_NUMBER STAFF_PHONE_E164 AWS_ACCESS_KEY_ID \
        AWS_SECRET_ACCESS_KEY AWS_REGION S3_BUCKET_NAME
      ;;
    resto)
      write_env_file "$ENV_DIR/resto.env" SECRET_KEY_BASE INTERNAL_API_TOKEN
      ;;
  esac
}
