#!/usr/bin/env bash

preview() {
  local action="${1:-}"
  shift || true
  case "$action" in
    deploy) preview_deploy "$@" ;;
    destroy) preview_destroy "$@" ;;
    destroy-pr) preview_destroy_pr "$@" ;;
    status) preview_status "${1:-}" ;;
    logs) preview_logs "${1:-}" "${2:-$DEFAULT_LOG_LINES}" ;;
    smoke) preview_smoke "${1:-}" ;;
    *) die "preview expects deploy, destroy, destroy-pr, status, logs, or smoke" ;;
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
  # preview ids are PR-keyed only — `pr-<number>`. storage (mysql,
  # redis, qdrant collection, clickhouse db, s3 prefix) persists across
  # commits for the same PR and is only torn down on PR close. each
  # commit just rolls forward the api + frontend image tags via
  # `compose up -d`; mysql/redis containers stay running.
  [[ "$preview_id" =~ ^pr-[0-9]+$ ]] \
    || die "preview id must look like pr-123"
}

preview_write_secure_file() {
  local path="$1"
  local tmp prev_umask
  prev_umask="$(umask)"
  umask 077
  tmp="$(mktemp)"
  cat > "$tmp"
  install -m 600 "$tmp" "$path"
  rm -f "$tmp"
  umask "$prev_umask"
}

# same as preview_write_secure_file but mode 644 — for files the container
# itself opens (not just the docker daemon). redis runs as uid 999 inside the
# image, so a 600 file owned by deploy is unreadable to it.
preview_write_readable_file() {
  local path="$1"
  local tmp prev_umask
  prev_umask="$(umask)"
  umask 022
  tmp="$(mktemp)"
  cat > "$tmp"
  install -m 644 "$tmp" "$path"
  rm -f "$tmp"
  umask "$prev_umask"
}

preview_deploy() {
  local preview_id="${1:-}"
  local api_tag="${2:-}"
  local frontend_tag="${3:-}"
  local host="${4:-}"
  [[ -n "$preview_id" && -n "$api_tag" && -n "$frontend_tag" && -n "$host" ]] \
    || die "usage: sfctl preview deploy <preview-id> <api-tag> <frontend-tag> <host>"
  preview_validate_id "$preview_id"

  local root
  root="$(preview_root "$preview_id")"
  mkdir -p "$root/env" "$root/data/mysql" "$root/data/redis" "$ROOT/caddy/previews"
  install -m 644 "$ROOT/compose.preview.yml" "$root/compose.preview.yml"

  # no destroy-others call here — preview_id is PR-keyed so there are
  # no sibling commit-previews to clean up. mysql/redis data persists
  # across commits within the same PR.
  preview_write_env "$preview_id" "$host" "$api_tag" "$frontend_tag" "$root"
  preview_prepare_clickhouse "$preview_id"
  preview_write_caddy "$preview_id" "$host"

  login_ghcr
  docker pull "$(image_ref api):$api_tag"
  docker pull "$(image_ref frontend):$frontend_tag"
  docker network create proxy_net 2>/dev/null || true

  preview_compose "$preview_id" up -d mysql redis
  preview_run_api_migrations "$preview_id" "$api_tag"
  preview_compose "$preview_id" up -d api frontend
  reload_caddy
  preview_status "$preview_id"
  preview_smoke "$preview_id"
  echo "sfctl: preview ready at https://$host"
}

preview_write_env() {
  local preview_id="$1"
  local host="$2"
  local api_tag="$3"
  local frontend_tag="$4"
  local root="$5"
  local mysql_root_pw mysql_pw redis_pw mysql_db clickhouse_db qdrant_collection s3_prefix

  # PR-stable credentials. on the first deploy of a PR these are
  # generated; on every subsequent commit they're reused from the
  # existing env files so the already-running mysql/redis containers
  # keep working. regenerating would break auth against the on-disk
  # data dirs (mysql refuses to start with a fresh root password
  # against an existing data dir).
  if [[ -f "$root/env/mysql.env" ]]; then
    mysql_root_pw="$(read_env_value "$root/env/mysql.env" MYSQL_ROOT_PASSWORD)"
    mysql_pw="$(read_env_value "$root/env/mysql.env" MYSQL_PASSWORD)"
    mysql_db="$(read_env_value "$root/env/mysql.env" MYSQL_DATABASE)"
  else
    mysql_root_pw="$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)"
    mysql_pw="$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)"
    mysql_db="${preview_id//-/_}"
  fi

  if [[ -f "$root/env/redis.env" ]]; then
    redis_pw="$(read_env_value "$root/env/redis.env" REDIS_PASSWORD)"
  else
    redis_pw="$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)"
  fi

  # PR-stable derived names. these don't need persistence (re-derived
  # the same way every deploy) but stay PR-keyed so the clickhouse
  # database / qdrant collection / s3 prefix outlive any single commit.
  clickhouse_db="${preview_id//-/_}"
  qdrant_collection="${QDRANT_COLLECTION:-transcript_embeddings}_${preview_id//-/_}"
  s3_prefix="preview/$preview_id"

  preview_write_secure_file "$root/env/preview.env" <<EOF
PREVIEW_ID=$preview_id
PREVIEW_HOST=$host
API_IMAGE_TAG=$api_tag
FRONTEND_IMAGE_TAG=$frontend_tag
EOF

  preview_write_secure_file "$root/env/images.env" <<EOF
API_IMAGE_TAG=$api_tag
FRONTEND_IMAGE_TAG=$frontend_tag
EOF

  preview_write_secure_file "$root/env/mysql.env" <<EOF
MYSQL_ROOT_PASSWORD=$mysql_root_pw
MYSQL_DATABASE=$mysql_db
MYSQL_USER=sf_voice
MYSQL_PASSWORD=$mysql_pw
EOF

  preview_write_secure_file "$root/env/redis.env" <<EOF
REDIS_USER=sf_voice
REDIS_PASSWORD=$redis_pw
REDIS_URL=redis://sf_voice:$redis_pw@${preview_id}-redis:6379
EOF

  preview_write_readable_file "$root/env/redis.users.acl" <<EOF
user default off
user sf_voice on >$redis_pw ~* &* +@all
EOF

  preview_write_secure_file "$root/env/api.env" <<EOF
DATABASE_URL=mysql://sf_voice:$mysql_pw@${preview_id}-mysql:3306/$mysql_db
REDIS_URL=redis://sf_voice:$redis_pw@${preview_id}-redis:6379
INTERNAL_API_TOKEN=${INTERNAL_API_TOKEN:-}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
CLICKHOUSE_URL=${CLICKHOUSE_URL:-}
CLICKHOUSE_DATABASE=$clickhouse_db
CLICKHOUSE_ACCESS_TOKEN=${CLICKHOUSE_ACCESS_TOKEN:-}
CLICKHOUSE_USER=${CLICKHOUSE_USER:-}
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD:-}
QDRANT_URL=${QDRANT_URL:-}
QDRANT_API_KEY=${QDRANT_API_KEY:-}
QDRANT_COLLECTION=$qdrant_collection
DIARIZE_URL=${DIARIZE_URL:-}
DIARIZE_API_KEY=${DIARIZE_API_KEY:-}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-}
AWS_REGION=${AWS_REGION:-}
S3_BUCKET_NAME=${S3_BUCKET_NAME:-}
S3_PREFIX=$s3_prefix
TWELVELABS_API_KEY=${TWELVELABS_API_KEY:-}
SF_VOICE_SECRETS_KEY=${SF_VOICE_SECRETS_KEY:-}
SF_VOICE_APP_URL=https://$host
SF_VOICE_SKIP_AWS_VERIFY=${SF_VOICE_SKIP_AWS_VERIFY:-}
COOKIE_SECURE=true
SF_VOICE_AWS_PRINCIPAL=${SF_VOICE_AWS_PRINCIPAL:-}
SF_VOICE_CFN_TEMPLATE_URL=${SF_VOICE_CFN_TEMPLATE_URL:-}
EOF
}

preview_prepare_clickhouse() {
  local preview_id="$1"
  local database="${preview_id//-/_}"
  [[ -n "${CLICKHOUSE_URL:-}" ]] || return 0
  preview_clickhouse_query "CREATE DATABASE IF NOT EXISTS \`$database\`"
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

preview_run_api_migrations() {
  local preview_id="$1"
  local api_tag="$2"
  local root
  root="$(preview_root "$preview_id")"
  docker run --rm --env-file "$root/env/api.env" --network proxy_net \
    "$(image_ref api):$api_tag" /usr/local/bin/migrate up
}

preview_write_caddy() {
  local preview_id="$1"
  local host="$2"
  cat > "$ROOT/caddy/previews/$preview_id.caddy" <<EOF
$host {
	tls /etc/caddy/certs/origin.pem /etc/caddy/certs/origin.key
	encode zstd gzip

	handle /api/* {
		reverse_proxy ${preview_id}-api:8080 {
			header_up X-Forwarded-Proto https
		}
	}

	handle /healthz {
		reverse_proxy ${preview_id}-api:8080 {
			header_up X-Forwarded-Proto https
		}
	}

	handle {
		reverse_proxy ${preview_id}-frontend:3000 {
			header_up X-Forwarded-Proto https
		}
	}
}
EOF
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
  # same bind-mount-owned-by-container-uid problem as preview_destroy_pr;
  # wipe via root container.
  docker run --rm -v "$ROOT/previews:/p" alpine:3 \
    sh -c "rm -rf /p/$preview_id" \
    || rm -rf "$root"
  reload_caddy
  echo "sfctl: preview destroyed: $preview_id"
}

preview_destroy_pr() {
  local pr_number="${1:-}"
  [[ "$pr_number" =~ ^[0-9]+$ ]] || die "preview pr number must be numeric"
  # PR-keyed: one preview per PR (pr-<n>). also glob the legacy
  # commit-keyed layout (preview-<n>-<sha>) so orphan previews from
  # before this change get cleaned up on PR close. both globs use
  # nullglob via the [[ -d ]] check inside the loop.
  local candidate candidate_id glob
  for glob in "$ROOT/previews/pr-$pr_number" "$ROOT/previews/preview-$pr_number-"*; do
    for candidate in $glob; do
      [[ -d "$candidate" ]] || continue
      candidate_id="$(basename "$candidate")"
      preview_cleanup_remote_storage "$candidate_id" || true
      preview_compose "$candidate_id" down -v --remove-orphans || true
      rm -f "$ROOT/caddy/previews/$candidate_id.caddy"
      # bind-mount-owned files inside $candidate (mysql/redis containers
      # chown their data dirs to uid 999) can't be unlinked by the deploy
      # user from the host. wipe via an ephemeral alpine container whose
      # root user has unrestricted access to the mount.
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

preview_host_for_id() {
  local preview_id="$1"
  local root host
  preview_validate_id "$preview_id"
  root="$(preview_root "$preview_id")"
  host="$(read_env_value "$root/env/preview.env" PREVIEW_HOST)"
  printf '%s' "${host:-$preview_id.sf-voice.sh}"
}

preview_smoke() {
  local preview_id="${1:-}"
  local host
  [[ -n "$preview_id" ]] || die "usage: sfctl preview smoke <preview-id>"
  host="$(preview_host_for_id "$preview_id")"
  curl -fsS "https://$host/healthz" >/dev/null
  curl -fsS "https://$host/" >/dev/null
}

reload_caddy() {
  if docker ps --format '{{.Names}}' | grep -qx caddy; then
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile
  fi
}
