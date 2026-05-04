#!/usr/bin/env bash
# one-time droplet setup. run as root from the cloned repo on the droplet:
#
#   sudo bash deploy/bootstrap.sh \
#     "<deploy_pubkey contents>" \
#     "<SECRET_KEY_BASE>" \
#     /path/to/origin.pem \
#     /path/to/origin.key
#
# after this, GitHub Actions can ssh as `deploy` and call deploy-resto-demo.sh.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "must run as root (try: sudo bash $0 ...)" >&2
  exit 1
fi

DEPLOY_PUBKEY="${1:?need deploy public key as arg 1}"
SECRET_KEY_BASE="${2:?need SECRET_KEY_BASE as arg 2}"
ORIGIN_CERT_PATH="${3:?need origin cert path as arg 3}"
ORIGIN_KEY_PATH="${4:?need origin key path as arg 4}"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "==> using repo at $REPO_DIR"

# ── 1. deploy user with docker access ────────────────────────────────────
if ! id -u deploy >/dev/null 2>&1; then
  echo "==> creating deploy user"
  useradd -m -s /bin/bash deploy
fi
usermod -aG docker deploy

install -d -o deploy -g deploy -m 700 /home/deploy/.ssh
echo "$DEPLOY_PUBKEY" > /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

# ── 2. directories ───────────────────────────────────────────────────────
mkdir -p /srv/caddy /srv/resto-demo /etc/caddy/certs

# the sqlite bind mount must be writable by the container user (uid 65534)
mkdir -p /srv/resto-demo/data
chown -R 65534:65534 /srv/resto-demo/data

# ── 3. cloudflare origin cert ────────────────────────────────────────────
install -m 644 "$ORIGIN_CERT_PATH" /etc/caddy/certs/origin.pem
install -m 600 "$ORIGIN_KEY_PATH"  /etc/caddy/certs/origin.key

# ── 4. drop configs ──────────────────────────────────────────────────────
install -m 644 "$REPO_DIR/deploy/Caddyfile"                  /srv/caddy/Caddyfile
install -m 644 "$REPO_DIR/deploy/docker-compose.caddy.yml"   /srv/caddy/docker-compose.yml
install -m 644 "$REPO_DIR/deploy/docker-compose.app.yml"     /srv/resto-demo/docker-compose.yml
install -m 755 "$REPO_DIR/deploy/deploy-resto-demo.sh"       /usr/local/bin/deploy-resto-demo.sh

# .env holds runtime secrets — chmod 600 so only deploy can read it
cat > /srv/resto-demo/.env <<EOF
SECRET_KEY_BASE=$SECRET_KEY_BASE
EOF
chown deploy:deploy /srv/resto-demo/.env
chmod 600 /srv/resto-demo/.env
# deploy needs to own the compose dir to be allowed to docker-compose there
chown -R deploy:deploy /srv/resto-demo
# but keep the data dir as nobody:nogroup so the container can write
chown -R 65534:65534 /srv/resto-demo/data

# ── 5. shared docker network ─────────────────────────────────────────────
docker network create proxy_net 2>/dev/null || true

# ── 6. start caddy (it'll keep running across app deploys) ───────────────
docker compose -f /srv/caddy/docker-compose.yml up -d

# ── 7. firewall ──────────────────────────────────────────────────────────
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  # only enable if not already enabled, and answer 'y' non-interactively
  ufw status | grep -q "Status: active" || echo "y" | ufw enable
fi

echo
echo "==> bootstrap complete"
echo "    deploy user: deploy"
echo "    caddy:       running on :80 / :443"
echo "    next deploy: from GitHub Actions on push to main"
echo "    smoke test:  curl -I https://resto-demo.sf-voice.sh"
