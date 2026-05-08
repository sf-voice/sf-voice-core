#!/usr/bin/env bash
# one-time droplet setup. run as root from the cloned repo on the droplet:
#
#   sudo bash deploy/bootstrap.sh \
#     "<deploy_pubkey contents>" \
#     "<RESTO_SECRET_KEY_BASE>" \
#     "<ELLIE_SECRET_KEY_BASE>" \
#     /path/to/origin.pem \
#     /path/to/origin.key
#
# after this, GitHub Actions can ssh as `deploy` and call:
#   /usr/local/bin/deploy-resto-demo.sh sha-<gitsha>
#   /usr/local/bin/deploy-ellie-ai.sh   sha-<gitsha>
# each app gets its own .env, its own compose stack, its own data dir.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "must run as root (try: sudo bash $0 ...)" >&2
  exit 1
fi

DEPLOY_PUBKEY="${1:?need deploy public key as arg 1}"
RESTO_SECRET_KEY_BASE="${2:?need resto SECRET_KEY_BASE as arg 2}"
ELLIE_SECRET_KEY_BASE="${3:?need ellie SECRET_KEY_BASE as arg 3}"
ORIGIN_CERT_PATH="${4:?need origin cert path as arg 4}"
ORIGIN_KEY_PATH="${5:?need origin key path as arg 5}"

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
mkdir -p /srv/caddy /srv/resto-demo /srv/ellie-ai /etc/caddy/certs

# the sqlite bind mount must be writable by the container user (uid 65534).
# ellie-ai has no on-disk state today, so no /data dir for it yet.
mkdir -p /srv/resto-demo/data
chown -R 65534:65534 /srv/resto-demo/data

# ── 3. cloudflare origin cert ────────────────────────────────────────────
install -m 644 "$ORIGIN_CERT_PATH" /etc/caddy/certs/origin.pem
install -m 600 "$ORIGIN_KEY_PATH"  /etc/caddy/certs/origin.key

# ── 4. drop configs ──────────────────────────────────────────────────────
install -m 644 "$REPO_DIR/deploy/Caddyfile"                  /srv/caddy/Caddyfile
install -m 644 "$REPO_DIR/deploy/docker-compose.caddy.yml"   /srv/caddy/docker-compose.yml
install -m 644 "$REPO_DIR/deploy/docker-compose.app.yml"     /srv/resto-demo/docker-compose.yml
install -m 644 "$REPO_DIR/deploy/docker-compose.ellie.yml"   /srv/ellie-ai/docker-compose.yml
install -m 755 "$REPO_DIR/deploy/deploy-resto-demo.sh"       /usr/local/bin/deploy-resto-demo.sh
install -m 755 "$REPO_DIR/deploy/deploy-ellie-ai.sh"         /usr/local/bin/deploy-ellie-ai.sh

# .env files hold runtime secrets — chmod 600 so only deploy can read them
cat > /srv/resto-demo/.env <<EOF
SECRET_KEY_BASE=$RESTO_SECRET_KEY_BASE
EOF

cat > /srv/ellie-ai/.env <<EOF
SECRET_KEY_BASE=$ELLIE_SECRET_KEY_BASE
EOF

# deploy owns the compose dirs so docker-compose works without sudo
chown -R deploy:deploy /srv/resto-demo /srv/ellie-ai
chmod 600 /srv/resto-demo/.env /srv/ellie-ai/.env

# but keep resto's data dir owned by nobody so the container can write to it
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
  ufw status | grep -q "Status: active" || echo "y" | ufw enable
fi

echo
echo "==> bootstrap complete"
echo "    deploy user:  deploy"
echo "    caddy:        running on :80 / :443"
echo "    apps wired:   resto-demo.sf-voice.sh, ellie-ai.sf-voice.sh"
echo "    next deploys: triggered by pushing to each app's path on main"
echo "    smoke tests:  curl -I https://resto-demo.sf-voice.sh"
echo "                  curl -I https://ellie-ai.sf-voice.sh"
