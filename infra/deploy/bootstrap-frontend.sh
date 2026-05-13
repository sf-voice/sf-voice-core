#!/usr/bin/env bash
# one-time droplet setup for the frontend static site. run as root:
#
#   sudo bash bootstrap-frontend.sh /path/to/repo
#
# what it does:
#   - creates /srv/frontend owned by the deploy user
#
# there's no .env (static build, no runtime secrets) and no data dir
# (nginx just serves files baked into the image).

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

echo "==> ensuring /srv/frontend exists and is owned by deploy"
mkdir -p /srv/frontend
chown deploy:deploy /srv/frontend

echo
echo "==> bootstrap-frontend complete"
echo "    next push to core/frontend/** builds the image, scp's the"
echo "    compose file, and brings up the container. no GH secrets"
echo "    needed — the frontend is a sealed static build."
