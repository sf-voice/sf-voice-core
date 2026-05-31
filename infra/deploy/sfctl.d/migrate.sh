#!/usr/bin/env bash

inventory() {
  ensure_dirs
  local ts report
  ts="$(date -u +%Y%m%d-%H%M%S)"
  report="$STATE_DIR/inventory/$ts.txt"
  {
    echo "sf-voice inventory $ts"
    echo
    echo "== /srv dirs =="
    find /srv -maxdepth 1 -mindepth 1 -print 2>/dev/null | sort || true
    echo
    echo "== docker containers =="
    docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
    echo
    echo "== docker compose projects =="
    docker compose ls || true
    echo
    echo "== bind mounts =="
    docker ps -aq | xargs -r docker inspect --format '{{.Name}} {{range .Mounts}}{{.Source}} -> {{.Destination}} {{end}}' || true
    echo
    echo "== systemd sf/mysql services =="
    systemctl list-units --all 'sf-voice*' 'mysql-backup*' --no-pager || true
    systemctl list-timers --all 'sf-voice*' 'mysql-backup*' --no-pager || true
    echo
    echo "== caddy paths =="
    ls -la /srv/caddy /etc/caddy/certs "$ROOT/caddy" "$ROOT/certs" 2>/dev/null || true
    echo
    echo "== current compose ps =="
    if [[ -f "$COMPOSE_FILE" ]]; then compose ps || true; fi
    echo
    echo "== recent logs =="
    for service in caddy frontend api ellie-ai resto-demo mysql qdrant redis; do
      echo "--- $service ---"
      docker logs --tail 80 "$service" 2>&1 || true
    done
  } | tee "$report"
  echo "sfctl: inventory saved to $report"
}

migrate_layout() {
  local mode="${1:---dry-run}"
  local dry_run=1
  case "$mode" in
    --dry-run) dry_run=1 ;;
    --apply) dry_run=0 ;;
    *) die "migrate-layout expects --dry-run or --apply" ;;
  esac

  if [[ "$dry_run" == "0" ]]; then
    need_root
    inventory >/dev/null
    ensure_dirs
  fi

  copy_legacy_layout "$dry_run"

  if [[ "$dry_run" == "0" ]]; then
    generate_data_service_envs
    chown -R deploy:deploy "$ROOT" 2>/dev/null || true
    chown -R 999:999 "$DATA_DIR/mysql" "$DATA_DIR/redis" 2>/dev/null || true
    chown -R 65534:65534 "$DATA_DIR/resto" "$DATA_DIR/ellie" 2>/dev/null || true
    stop_legacy_stacks
    echo "sfctl: layout migrated; run 'sfctl deploy all latest' after image/env review"
  else
    echo "sfctl: dry run only; rerun with --apply during the maintenance window"
  fi
}

copy_legacy_layout() {
  local dry_run="$1"
  copy_if_exists /srv/mysql/data/ "$DATA_DIR/mysql/" "$dry_run"
  copy_if_exists /srv/mysql/backups/ "$DATA_DIR/mysql-backups/" "$dry_run"
  copy_if_exists /srv/qdrant/data/ "$DATA_DIR/qdrant/" "$dry_run"
  copy_if_exists /srv/redis/data/ "$DATA_DIR/redis/" "$dry_run"
  copy_if_exists /srv/resto-demo/data/ "$DATA_DIR/resto/" "$dry_run"
  copy_if_exists /srv/ellie-ai/data/ "$DATA_DIR/ellie/" "$dry_run"
  copy_if_exists /srv/mysql/.env "$ENV_DIR/mysql.env" "$dry_run"
  copy_if_exists /srv/redis/.env "$ENV_DIR/redis.env" "$dry_run"
  copy_if_exists /srv/redis/users.acl "$ENV_DIR/redis.users.acl" "$dry_run"
  copy_if_exists /srv/resto-demo/.env "$ENV_DIR/resto.env" "$dry_run"
  copy_if_exists /srv/ellie-ai/.env "$ENV_DIR/ellie.env" "$dry_run"
  copy_if_exists /srv/sf-voice-api/.env "$ENV_DIR/api.env" "$dry_run"
  copy_if_exists /srv/caddy/Caddyfile "$ROOT/caddy/Caddyfile" "$dry_run"
  copy_if_exists /etc/caddy/certs/origin.pem "$ROOT/certs/origin.pem" "$dry_run"
  copy_if_exists /etc/caddy/certs/origin.key "$ROOT/certs/origin.key" "$dry_run"
}

copy_if_exists() {
  local src="$1"
  local dst="$2"
  local dry_run="$3"
  if [[ ! -e "$src" ]]; then
    echo "skip missing $src"
    return
  fi
  echo "copy $src -> $dst"
  if [[ "$dry_run" == "0" ]]; then
    mkdir -p "$(dirname "$dst")"
    rsync -a "$src" "$dst"
  fi
}

stop_legacy_stacks() {
  echo "sfctl: stopping legacy compose stacks so container names are free"
  for dir in "${OLD_DIRS[@]}"; do
    if [[ -f "$dir/docker-compose.yml" ]]; then
      docker compose -f "$dir/docker-compose.yml" down --remove-orphans || true
    fi
  done
}

cleanup() {
  local action="${1:---dry-run}"
  local stamp="${2:-$(date -u +%Y%m%d)}"
  local archive="/srv/.archive-$stamp"

  case "$action" in
    --dry-run) cleanup_dry_run "$archive" ;;
    --archive) archive_legacy_dirs "$archive" ;;
    --delete-archive) delete_archive "$stamp" "$archive" ;;
    *) die "cleanup expects --dry-run, --archive, or --delete-archive YYYYMMDD" ;;
  esac
}

cleanup_dry_run() {
  local archive="$1"
  local found=0
  for dir in "${OLD_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      echo "would archive $dir -> $archive/$(basename "$dir")"
      found=1
    fi
  done
  [[ "$found" == "1" ]] || echo "no legacy /srv dirs found"
}

archive_legacy_dirs() {
  local archive="$1"
  need_root
  mkdir -p "$archive"
  for dir in "${OLD_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      mv "$dir" "$archive/$(basename "$dir")"
      echo "archived $dir -> $archive/$(basename "$dir")"
    fi
  done
}

delete_archive() {
  local stamp="$1"
  local archive="$2"
  need_root
  [[ "$stamp" =~ ^[0-9]{8}$ ]] || die "archive date must be YYYYMMDD"
  [[ -d "$archive" ]] || die "archive not found: $archive"
  rm -rf --one-file-system "$archive"
  echo "deleted $archive"
}
