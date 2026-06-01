#!/usr/bin/env bash

bootstrap() {
  need_root
  ensure_dirs
  install_bootstrap_assets
  ensure_images_env
  generate_data_service_envs

  chown -R deploy:deploy "$ROOT" 2>/dev/null || true
  chown -R 999:999 "$DATA_DIR/mysql" "$DATA_DIR/redis" 2>/dev/null || true
  chown -R 65534:65534 "$DATA_DIR/resto" "$DATA_DIR/ellie" 2>/dev/null || true

  docker network create proxy_net 2>/dev/null || true
  install_mysql_backup_timer
  echo "sfctl: bootstrap complete at $ROOT"
}

install_bootstrap_assets() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  install_asset "$script_dir/compose.prod.yml" "$RAW_BASE/compose.prod.yml" "$COMPOSE_FILE" 644
  install_asset "$script_dir/Caddyfile" "$RAW_BASE/Caddyfile" "$ROOT/caddy/Caddyfile" 644
  install_asset "$script_dir/smoke-vad.py" "$RAW_BASE/smoke-vad.py" "$ROOT/smoke-vad.py" 755
  install_asset "$script_dir/sfctl.sh" "$RAW_BASE/sfctl.sh" "$BIN_DIR/sfctl" 755

  mkdir -p "$BIN_DIR/sfctl.d"
  for file in common bootstrap migrate deploy; do
    install_asset "$script_dir/sfctl.d/$file.sh" "$RAW_BASE/sfctl.d/$file.sh" "$BIN_DIR/sfctl.d/$file.sh" 644
  done
}

install_asset() {
  local local_path="$1"
  local raw_url="$2"
  local target="$3"
  local mode="$4"
  local tmp
  if [[ -f "$local_path" ]]; then
    install -m "$mode" "$local_path" "$target"
    return
  fi
  tmp="$(mktemp)"
  # bound the fetch so an unreachable host or stalled server can't hang bootstrap.
  curl -fsSL --connect-timeout 10 --max-time 30 "$raw_url" -o "$tmp"
  install -m "$mode" "$tmp" "$target"
  rm -f "$tmp"
}

generate_data_service_envs() {
  mkdir -p "$ENV_DIR"
  generate_mysql_env
  generate_redis_env
}

generate_mysql_env() {
  # if mysql.env already exists, skip generation. use `return 0` not bare
  # `return` — bare return propagates $? from the [[ ]] test, which is 1 here.
  [[ ! -f "$ENV_DIR/mysql.env" ]] || return 0
  local root_pw app_pw
  root_pw="$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)"
  app_pw="$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)"
  cat > "$ENV_DIR/mysql.env" <<EOF
MYSQL_ROOT_PASSWORD=$root_pw
MYSQL_DATABASE=sf_voice
MYSQL_USER=sf_voice
MYSQL_PASSWORD=$app_pw
EOF
  chmod 600 "$ENV_DIR/mysql.env"
  echo "sfctl: mysql credentials generated in $ENV_DIR/mysql.env"
  echo "sfctl: api DATABASE_URL should be mysql://sf_voice:$app_pw@mysql:3306/sf_voice"
}

generate_redis_env() {
  if [[ ! -f "$ENV_DIR/redis.env" ]]; then
    local redis_pw
    redis_pw="$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)"
    cat > "$ENV_DIR/redis.env" <<EOF
REDIS_USER=sf_voice
REDIS_PASSWORD=$redis_pw
REDIS_URL=redis://sf_voice:$redis_pw@redis:6379
EOF
    chmod 600 "$ENV_DIR/redis.env"
    echo "sfctl: redis credentials generated in $ENV_DIR/redis.env"
    echo "sfctl: api REDIS_URL should be redis://sf_voice:$redis_pw@redis:6379"
  fi

  # shellcheck disable=SC1091
  . "$ENV_DIR/redis.env"
  cat > "$ENV_DIR/redis.users.acl" <<EOF
user default off
user $REDIS_USER on >$REDIS_PASSWORD ~* &* +@all
EOF
  chmod 600 "$ENV_DIR/redis.users.acl"
}

install_mysql_backup_timer() {
  need_root
  cat > /etc/systemd/system/sf-voice-mysql-backup.service <<EOF
[Unit]
Description=daily sf-voice mysql backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$BIN_DIR/sfctl mysql-backup
EOF

  cat > /etc/systemd/system/sf-voice-mysql-backup.timer <<'EOF'
[Unit]
Description=run sf-voice mysql backup daily

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now sf-voice-mysql-backup.timer
}

mysql_backup() {
  local backup_dir="$DATA_DIR/mysql-backups"
  local db_name="sf_voice"
  local ts out
  mkdir -p "$backup_dir"
  ts="$(date -u +%Y%m%d-%H%M%S)"
  out="$backup_dir/$db_name-$ts.sql.gz"
  docker exec mysql sh -c \
    'exec mysqldump --single-transaction --quick --routines --triggers -u root -p"$MYSQL_ROOT_PASSWORD" "'"$db_name"'"' \
    | gzip > "$out"
  chmod 600 "$out"
  chown deploy:deploy "$out" 2>/dev/null || true
  find "$backup_dir" -name "$db_name-*.sql.gz" -mtime +7 -delete
  echo "sfctl: mysql backup wrote $out"
}
