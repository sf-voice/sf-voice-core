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
  login_ghcr
  write_service_env "$service"
  prepare_image "$service" "$tag"
  run_api_migrations_if_needed "$service" "$tag"
  compose up -d --no-deps "$compose_service"
  seed_if_needed "$service"
  docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true
  status_service "$service"
  [[ "${SFCTL_SKIP_SMOKE:-0}" == "1" ]] || smoke "$service"
}

deploy_all() {
  local tag="$1"
  for item in mysql qdrant redis caddy resto ellie api frontend; do
    SFCTL_SKIP_SMOKE=1 deploy_service "$item" "$tag"
  done
  smoke all
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
  [[ "$service" == "api" ]] || return
  compose pull api
  docker run --rm --env-file "$ENV_DIR/api.env" --network proxy_net \
    "$(image_ref api):$tag" /usr/local/bin/migrate up
}

migrate_staging() {
  local api_tag="$1"
  [[ -n "$api_tag" ]] || die "migrate-staging needs an api tag"
  ensure_preview_runtime
  login_ghcr
  write_staging_api_env
  docker pull "$(image_ref api):$api_tag"
  docker run --rm --env-file "$ENV_DIR/staging-api.env" --network proxy_net \
    -e QDRANT_URL=http://staging-qdrant:6334 \
    "$(image_ref api):$api_tag" /usr/local/bin/migrate up
  echo "sfctl: staging migrations passed for $api_tag"
}

deploy_preview() {
  local pr="$1"
  local frontend_tag="$2"
  local api_tag="$3"
  validate_preview_pr "$pr"
  [[ -n "$frontend_tag" ]] || die "deploy-preview needs a frontend tag"
  [[ -n "$api_tag" ]] || die "deploy-preview needs an api tag"

  ensure_preview_runtime
  login_ghcr
  write_staging_api_env
  docker pull "$(image_ref frontend):$frontend_tag"
  docker pull "$(image_ref api):$api_tag"
  recreate_preview_container "$pr" api "$api_tag"
  recreate_preview_container "$pr" frontend "$frontend_tag"
  docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true
  smoke_preview "$pr"
}

cleanup_preview() {
  local pr="$1"
  validate_preview_pr "$pr"
  docker rm -f "preview-pr-$pr-api" "preview-pr-$pr-frontend" >/dev/null 2>&1 || true
  rm -f "$PREVIEW_DIR/pr-$pr.env"
  echo "sfctl: cleaned preview pr-$pr"
}

ensure_preview_runtime() {
  ensure_dirs
  docker network create proxy_net >/dev/null 2>&1 || true
  generate_staging_data_service_envs
  write_staging_api_env
  compose up -d caddy staging-mysql staging-qdrant staging-redis
}

recreate_preview_container() {
  local pr="$1"
  local service="$2"
  local tag="$3"
  local container="preview-pr-$pr-$service"
  docker rm -f "$container" >/dev/null 2>&1 || true

  case "$service" in
    api)
      docker run -d \
        --name "$container" \
        --restart unless-stopped \
        --env-file "$ENV_DIR/staging-api.env" \
        --network proxy_net \
        -e RUST_LOG="${RUST_LOG:-info}" \
        -e VAD_WS_URL="${STAGING_VAD_WS_URL:-ws://127.0.0.1:1/socket/vad}" \
        -e QDRANT_URL=http://staging-qdrant:6334 \
        -e SF_VOICE_APP_URL="https://pr-$pr.sf-voice.sh" \
        "$(image_ref api):$tag"
      ;;
    frontend)
      docker run -d \
        --name "$container" \
        --restart unless-stopped \
        --network proxy_net \
        "$(image_ref frontend):$tag"
      ;;
    *)
      die "unknown preview service: $service"
      ;;
  esac
}

smoke_preview() {
  local pr="$1"
  curl -fsS "https://pr-$pr.sf-voice.sh/healthz" >/dev/null
  curl -fsS "https://pr-$pr.sf-voice.sh/" >/dev/null
  echo "sfctl: preview ready at https://pr-$pr.sf-voice.sh"
}

seed_if_needed() {
  case "$1" in
    ellie) seed_ellie || true ;;
    resto) seed_resto || true ;;
  esac
}

seed_ellie() {
  wait_for_rpc ellie-ai /app/bin/ellie_ai 60
  compose exec -T ellie-ai /app/bin/ellie_ai eval "EllieAi.Release.seed()"
}

seed_resto() {
  wait_for_rpc resto-demo /app/bin/resto_booking_app 30
  compose exec -T resto-demo /app/bin/resto_booking_app eval "RestoBookingApp.Release.seed()"
}

wait_for_rpc() {
  local service="$1"
  local bin="$2"
  local tries="$3"
  for i in $(seq 1 "$tries"); do
    if compose exec -T "$service" "$bin" rpc "IO.puts(:up)" >/dev/null 2>&1; then
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
    mysql|qdrant|redis) compose ps "$(service_name "$service")" ;;
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
  local tag_sha="${FRONTEND_IMAGE_TAG#sha-}"
  local body
  body="$(curl -fsS https://app.sf-voice.sh/version.json)"
  if [[ "$FRONTEND_IMAGE_TAG" == sha-* && "$body" != *"\"sha\":\"$tag_sha\""* ]]; then
    die "frontend version.json does not match $FRONTEND_IMAGE_TAG: $body"
  fi
}
