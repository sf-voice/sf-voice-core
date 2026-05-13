#!/usr/bin/env bash
# daily mysqldump runner. installed at /usr/local/bin/mysql-backup.sh by
# bootstrap-mysql.sh, fired by mysql-backup.timer at 03:30 droplet-local.
#
# writes gzipped dumps to /srv/mysql/backups/<db>-<utc-date>.sql.gz and
# prunes anything older than RETENTION_DAYS. local-only — when the data is
# worth more than a droplet snapshot, swap this for an off-droplet push.

set -euo pipefail

BACKUP_DIR="/srv/mysql/backups"
RETENTION_DAYS=7
DB_NAME="sf_voice"

mkdir -p "$BACKUP_DIR"

ts="$(date -u +%Y%m%d-%H%M%S)"
out="$BACKUP_DIR/$DB_NAME-$ts.sql.gz"

# dump from inside the container so we don't need the mysql client on the
# host. root password lives in /srv/mysql/.env which docker compose loaded
# into the container's env at start.
docker exec mysql sh -c \
  'exec mysqldump --single-transaction --quick --routines --triggers \
     -u root -p"$MYSQL_ROOT_PASSWORD" "'"$DB_NAME"'"' \
  | gzip > "$out"

chmod 600 "$out"
chown deploy:deploy "$out"

# prune old dumps. -mtime is "modified more than N days ago"; +7 = older
# than a week. quiet if there's nothing to prune.
find "$BACKUP_DIR" -name "$DB_NAME-*.sql.gz" -mtime +"$RETENTION_DAYS" -delete

echo "mysql-backup: wrote $out"
