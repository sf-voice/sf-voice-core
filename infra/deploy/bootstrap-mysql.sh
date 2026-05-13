#!/usr/bin/env bash
# one-time droplet setup for on-prem MySQL. run as root from the cloned repo:
#
#   sudo bash infra/deploy/bootstrap-mysql.sh /path/to/resto-booking-app
#
# what it does:
#   - creates /srv/mysql/{data,backups} with correct ownership
#   - generates root password + app password and writes /srv/mysql/.env
#     (chmod 600 — only deploy and root can read)
#   - installs docker-compose.mysql.yml at /srv/mysql/docker-compose.yml
#   - installs mysql-backup.sh at /usr/local/bin/mysql-backup.sh and
#     wires up a daily systemd timer to run it
#   - brings the stack up
#
# safe to re-run: skips secret generation if /srv/mysql/.env already exists,
# so re-running doesn't rotate passwords and disconnect live clients.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "must run as root (try: sudo bash $0 ...)" >&2
  exit 1
fi

REPO_DIR="${1:?need path to the resto-booking-app repo as arg 1}"

if [[ ! -d "$REPO_DIR/infra/deploy" ]]; then
  echo "no infra/deploy under $REPO_DIR — wrong path?" >&2
  exit 1
fi

DB_NAME="sf_voice"
DB_USER="sf_voice"

# ── 1. dirs ──────────────────────────────────────────────────────────────
echo "==> ensuring /srv/mysql exists"
mkdir -p /srv/mysql/data /srv/mysql/backups
# mysql:8 image runs as uid 999.
chown -R 999:999 /srv/mysql/data
chown deploy:deploy /srv/mysql /srv/mysql/backups

# ── 2. .env with root + app credentials ──────────────────────────────────
if [[ -f /srv/mysql/.env ]]; then
  echo "==> /srv/mysql/.env already exists — leaving credentials alone"
else
  echo "==> generating root + app passwords"
  root_pw="$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)"
  app_pw="$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)"
  cat > /srv/mysql/.env <<EOF
MYSQL_ROOT_PASSWORD=$root_pw
MYSQL_DATABASE=$DB_NAME
MYSQL_USER=$DB_USER
MYSQL_PASSWORD=$app_pw
EOF
  chown deploy:deploy /srv/mysql/.env
  chmod 600 /srv/mysql/.env
  echo "==> credentials written to /srv/mysql/.env"
  echo "    app connection string for the rust api:"
  echo "      mysql://$DB_USER:$app_pw@mysql:3306/$DB_NAME"
fi

# ── 3. compose file ──────────────────────────────────────────────────────
echo "==> installing /srv/mysql/docker-compose.yml"
install -m 644 -o deploy -g deploy \
  "$REPO_DIR/infra/deploy/docker-compose.mysql.yml" \
  /srv/mysql/docker-compose.yml

# ── 4. backup script + daily timer ───────────────────────────────────────
echo "==> installing /usr/local/bin/mysql-backup.sh"
install -m 755 "$REPO_DIR/infra/deploy/mysql-backup.sh" /usr/local/bin/mysql-backup.sh

# systemd unit + timer for daily backups at 03:30 droplet-local time.
# mysqldump runs inside the mysql container, so no client tools needed on
# the host. retention is 7 days, enforced by the script itself.
cat > /etc/systemd/system/mysql-backup.service <<'EOF'
[Unit]
Description=daily mysqldump of /srv/mysql to /srv/mysql/backups
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mysql-backup.sh
EOF

cat > /etc/systemd/system/mysql-backup.timer <<'EOF'
[Unit]
Description=run mysql-backup daily

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now mysql-backup.timer

# ── 5. proxy_net network (created by bootstrap.sh; ensure it exists) ─────
docker network create proxy_net 2>/dev/null || true

# ── 6. bring the stack up ────────────────────────────────────────────────
echo "==> starting mysql"
docker compose -f /srv/mysql/docker-compose.yml up -d

echo
echo "==> bootstrap-mysql complete"
echo "    container:    mysql (on proxy_net)"
echo "    data:         /srv/mysql/data"
echo "    backups:      /srv/mysql/backups (daily 03:30, 7-day retention)"
echo "    credentials:  /srv/mysql/.env (chmod 600)"
echo
echo "    reach it from another container on proxy_net as:"
echo "      mysql://$DB_USER:<password>@mysql:3306/$DB_NAME"
