#!/usr/bin/env bash

login_ghcr() {
  if [[ -n "${GHCR_TOKEN:-}" && -n "${GHCR_USER:-}" ]]; then
    echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
  fi
}

deploy_service() {
  local service="$1"
  local tag="$2"
  [[ -n "$tag" ]] || die "deploy needs a tag"

  if [[ "$service" == "all" ]]; then
    deploy_all "$tag"
    return
  fi

  local compose_service
  compose_service="$(service_name "$service")"
  ensure_dirs
  ensure_prod_networks
  login_ghcr
  write_service_env "$service"
  prepare_image "$service" "$tag"
  ensure_runtime_dependencies "$service"
  run_api_migrations_if_needed "$service" "$tag"
  compose up -d --no-deps "$compose_service"
  seed_if_needed "$service"
  docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true
  status_service "$service"
  [[ "${SFCTL_SKIP_SMOKE:-0}" == "1" ]] || smoke "$service"
}

deploy_all() {
  local tag="$1"
  for item in mysql redis caddy resto ellie api frontend; do
    SFCTL_SKIP_SMOKE=1 deploy_service "$item" "$tag"
  done
  smoke all
}

ensure_runtime_dependencies() {
  case "$1" in
    api)
      compose up -d --no-deps mysql redis
      ;;
    caddy)
      ensure_caddy_certs
      ;;
  esac
}

ensure_caddy_certs() {
  [[ -f "$ROOT/certs/origin.pem" ]] || die "missing caddy cert: $ROOT/certs/origin.pem"
  [[ -f "$ROOT/certs/origin.key" ]] || die "missing caddy cert: $ROOT/certs/origin.key"
}

prepare_image() {
  local service="$1"
  local tag="$2"
  case "$service" in
    frontend|api|ellie|resto)
      set_image_tag "$service" "$tag"
      docker pull "$(image_ref "$service"):$tag"
      ;;
    *)
      compose pull "$(service_name "$service")" || true
      ;;
  esac
}

run_api_migrations_if_needed() {
  local service="$1"
  local tag="$2"
  # bare `return` propagates the previous command's exit code — when the [[ ]]
  # test fails for non-api services it sets $? to 1, and set -e kills the whole
  # deploy before compose up ever runs. always return 0 to short-circuit cleanly.
  [[ "$service" == "api" ]] || return 0
  compose pull api
  docker run --rm --env-file "$ENV_DIR/api.env" --network proxy_net \
    "$(image_ref api):$tag" /usr/local/bin/migrate up
}

seed_if_needed() {
  case "$1" in
    ellie) seed_ellie || true ;;
    resto) seed_resto || true ;;
  esac
}

seed_ellie() {
  wait_for_rpc ellie-ai /app/bin/ellie_ai 60
  docker exec ellie-ai /app/bin/ellie_ai eval "EllieAi.Release.seed()"
}

seed_resto() {
  wait_for_rpc resto-demo /app/bin/resto_booking_app 30
  docker exec resto-demo /app/bin/resto_booking_app eval "RestoBookingApp.Release.seed()"
}

wait_for_rpc() {
  local service="$1"
  local bin="$2"
  local tries="$3"
  for i in $(seq 1 "$tries"); do
    if docker exec "$service" "$bin" rpc "IO.puts(:up)" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  die "$service did not become rpc-ready"
}

restart_service() {
  local service="$1"
  if [[ "$service" == "all" ]]; then
    compose restart
  else
    compose restart "$(service_name "$service")"
  fi
}

status_service() {
  local service="${1:-all}"
  echo "== compose ps =="
  if [[ "$service" == "all" ]]; then
    compose ps
  else
    compose ps "$(service_name "$service")"
  fi

  echo
  echo "== image tags =="
  [[ -f "$ENV_DIR/images.env" ]] && cat "$ENV_DIR/images.env" || true

  echo
  echo "== running revisions =="
  for container in $(containers_for "$service"); do
    echo "--- $container ---"
    docker inspect "$container" --format 'image={{.Config.Image}} digest={{.Image}} revision={{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null || true
  done

  if [[ "$service" == "frontend" || "$service" == "all" ]]; then
    echo
    echo "== frontend public version =="
    curl -fsS https://app.sf-voice.sh/version.json || true
    echo
  fi
}

logs_service() {
  local service="${1:?logs needs a service}"
  local lines="${2:-$DEFAULT_LOG_LINES}"
  if [[ "$service" == "all" ]]; then
    for container in $(containers_for all); do
      echo "--- $container ---"
      docker logs --tail "$lines" "$container" 2>&1 || true
    done
  else
    docker logs --tail "$lines" "$(service_name "$service")" 2>&1
  fi
}

smoke() {
  local service="${1:-all}"
  case "$service" in
    frontend) smoke_frontend ;;
    api) curl -fsS https://app.sf-voice.sh/healthz >/dev/null ;;
    ellie) smoke_ellie ;;
    resto) curl -fsS https://resto-demo.sf-voice.sh/api/menu >/dev/null ;;
    caddy) curl -fsS https://app.sf-voice.sh/ >/dev/null ;;
    mysql|redis) compose ps "$(service_name "$service")" ;;
    all) smoke resto; smoke ellie; smoke api; smoke frontend ;;
    *) die "unknown service: $service" ;;
  esac
  echo "sfctl: smoke passed for $service"
}

smoke_frontend() {
  curl -fsS https://app.sf-voice.sh/ >/dev/null
  verify_frontend_version
}

smoke_ellie() {
  curl -fsS https://ellie-ai.sf-voice.sh/ >/dev/null
  if [[ -n "${INTERNAL_API_TOKEN:-}" && -f "$ROOT/smoke-vad.py" ]]; then
    python3 "$ROOT/smoke-vad.py" wss://ellie-ai.sf-voice.sh/socket/vad "$INTERNAL_API_TOKEN"
  fi
}

verify_frontend_version() {
  ensure_images_env
  # shellcheck disable=SC1091
  . "$ENV_DIR/images.env"

  # only validate sha-tagged builds. `:latest` and other floating tags can't
  # be cross-checked against a specific commit, so skip.
  [[ "$FRONTEND_IMAGE_TAG" == sha-* ]] || return 0

  local tag_sha="${FRONTEND_IMAGE_TAG#sha-}"

  # nginx (core/frontend/nginx.conf) emits X-App-Sha with the git sha baked
  # in at image build time. read it from a HEAD so we don't pull the whole
  # SPA payload. `tr` strips both whitespace and the trailing \r curl leaves
  # on header values.
  local served_sha
  served_sha="$(curl -fsSI https://app.sf-voice.sh/ \
    | awk -F': ' 'tolower($1)=="x-app-sha" {print $2; exit}' \
    | tr -d '[:space:]')"

  if [[ -z "$served_sha" ]]; then
    die "frontend missing X-App-Sha header — image too old or nginx config broken"
  fi
  if [[ "$served_sha" != "$tag_sha" ]]; then
    die "frontend X-App-Sha mismatch: expected $tag_sha, got $served_sha"
  fi
}
