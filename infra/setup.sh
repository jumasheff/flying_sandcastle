#!/usr/bin/env bash
# Install the Flying Sandcastle factory on a fresh Ubuntu 24.04 server.
# Run as root from a clone of this repo:  sudo ./infra/setup.sh
# Safe to run again (for example after `git pull`).
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
SRC="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY_DIR=/opt/factory
CONFIG_DIR=/etc/factory
WORK_DIR=/var/lib/factory

export DEBIAN_FRONTEND=noninteractive

echo "==> System packages"
apt-get update -q
apt-get install -yq ca-certificates curl git jq gnupg ufw unattended-upgrades

if ! command -v docker >/dev/null; then
  echo "==> Docker"
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  echo "==> Node.js 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -yq nodejs
fi

if ! command -v gh >/dev/null; then
  echo "==> GitHub CLI"
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -q && apt-get install -yq gh
fi

if ! command -v flyctl >/dev/null; then
  echo "==> flyctl (staging deploys)"
  curl -fsSL https://fly.io/install.sh | FLYCTL_INSTALL=/usr/local sh
fi

if ! command -v tailscale >/dev/null; then
  echo "==> Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# Swap: Next.js builds in parallel sandboxes can spike memory.
if ! swapon --show | grep -q .; then
  echo "==> 4 GB swap"
  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

echo "==> factory user"
id factory >/dev/null 2>&1 || useradd --system --create-home --home-dir /home/factory --shell /bin/bash factory
usermod -aG docker factory

echo "==> Files"
mkdir -p "$FACTORY_DIR" "$CONFIG_DIR" "$WORK_DIR"
# Copy the factory code (not .git) so the running copy changes only when you run setup again.
tar -C "$SRC" --exclude=.git --exclude=node_modules -cf - . | tar -C "$FACTORY_DIR" -xf -
chown -R factory:factory "$FACTORY_DIR" "$WORK_DIR"
[ -f "$CONFIG_DIR/factory.env" ] || install -m 644 "$SRC/factory.env.example" "$CONFIG_DIR/factory.env"
[ -f "$CONFIG_DIR/secrets.env" ] || install -m 600 -o factory -g factory "$SRC/secrets.env.example" "$CONFIG_DIR/secrets.env"
[ -f "$CONFIG_DIR/host-secrets.env" ] || install -m 600 -o factory -g factory "$SRC/host-secrets.env.example" "$CONFIG_DIR/host-secrets.env"

echo "==> npm install"
sudo -u factory -H bash -c "cd $FACTORY_DIR && npm install --omit=dev --no-audit --no-fund"

echo "==> systemd"
install -m 644 "$SRC/infra/factory.service" /etc/systemd/system/factory.service
install -m 644 "$SRC/infra/factory.timer" /etc/systemd/system/factory.timer
systemctl daemon-reload

echo "==> Firewall: SSH only (Tailscale traffic is allowed on its own interface)"
ufw allow OpenSSH >/dev/null
ufw allow in on tailscale0 >/dev/null
ufw --force enable >/dev/null

cat <<MSG

Done. Next steps:
  1. sudo nano $CONFIG_DIR/factory.env    # TARGET_REPO=owner/name
  2. sudo nano $CONFIG_DIR/secrets.env    # CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN
     sudo nano $CONFIG_DIR/host-secrets.env  # FLY_API_TOKEN, STAGING_DB_URL (docs/staging.md)
  3. sudo tailscale up --ssh              # optional: SSH from your phone over Tailscale
  4. sudo systemctl start factory && journalctl -u factory -f    # first run by hand
  5. sudo systemctl enable --now factory.timer                   # then every 20 minutes
MSG
