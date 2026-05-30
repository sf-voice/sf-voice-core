#!/usr/bin/env bash
# one-time droplet setup for sf-voice-api. run as root:
#
#   sudo bash bootstrap-api.sh /path/to/repo
#
# what it does:
#   - creates /srv/sf-voice-api owned by the deploy user
#
# what it does NOT do:
#   - write /srv/sf-voice-api/.env. CI (.github/workflows/sf-voice-api.yml)
#     is the source of truth for that file.

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

echo "==> ensuring /srv/sf-voice-api exists and is owned by deploy"
mkdir -p /srv/sf-voice-api
chown deploy:deploy /srv/sf-voice-api

echo
echo "==> bootstrap-api complete"
echo "    next push to core/backend/** writes /srv/sf-voice-api/.env"
echo "    from GH secrets and brings up the container. ensure these GH"
echo "    secrets are populated before you push:"
echo "      DATABASE_URL  (mysql connection string)"
