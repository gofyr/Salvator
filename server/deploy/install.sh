#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Try to find server binary next to script or one level up (../cmd build output not assumed)
if [[ -x "$SCRIPT_DIR/../server" ]]; then BIN="$SCRIPT_DIR/../server"; fi
if [[ -z "${BIN:-}" && -x "$SCRIPT_DIR/server" ]]; then BIN="$SCRIPT_DIR/server"; fi
if [[ -z "${BIN:-}" ]]; then
  echo "Could not locate server binary next to installer. Place 'server' in $(dirname "$SCRIPT_DIR") or $SCRIPT_DIR" >&2
  exit 1
fi
DEST_DIR="/opt/server-monitor"
STATE_DIR="/var/lib/server-monitor"
CONF_DIR="/etc/server-monitor"
TLS_DIR="$CONF_DIR/tls"
UNIT="/etc/systemd/system/server-monitor.service"

read -rp "Username [admin]: " SM_USER
SM_USER=${SM_USER:-admin}
read -rsp "Password (will be hashed): " SM_PASS; echo
read -rsp "Client key (will be hashed): " SM_KEY; echo

id -u servermon >/dev/null 2>&1 || useradd --system --home "$STATE_DIR" --shell /sbin/nologin servermon

install -d -m 0750 -o servermon -g servermon "$DEST_DIR" "$STATE_DIR" "$CONF_DIR" "$TLS_DIR"

install -m 0755 "$BIN" "$DEST_DIR/server"

cat > "$CONF_DIR/config.yaml" <<EOF
listen_address: ":8888"
data_dir: "$STATE_DIR"
tls_cert_path: "$STATE_DIR/server.crt"
tls_key_path: "$STATE_DIR/server.key"
require_client_ca: false
username: "$SM_USER"
password_hash: "${SM_PASS}"
jwt_secret: ""
access_ttl: "15m"
refresh_ttl: "168h"
client_key_hash: "${SM_KEY}"
EOF

chown servermon:servermon "$CONF_DIR/config.yaml"
chmod 0640 "$CONF_DIR/config.yaml"

# Generate TLS
sudo -u servermon "$DEST_DIR/server" -config "$CONF_DIR/config.yaml" -gen-cert

# Replace plaintext secrets with bcrypt using built-in hasher
PHASH=$("$DEST_DIR/server" -hash "$SM_PASS")
KHASH=$("$DEST_DIR/server" -hash "$SM_KEY")
sed -i "s|^password_hash: \".*\"|password_hash: \"$PHASH\"|" "$CONF_DIR/config.yaml"
sed -i "s|^client_key_hash: \".*\"|client_key_hash: \"$KHASH\"|" "$CONF_DIR/config.yaml"

# Update config with hashed values if empty
PASS_HASH=$(openssl passwd -6 "$SM_PASS" 2>/dev/null || true)
if grep -q '^password_hash: ""' "$CONF_DIR/config.yaml"; then
  # fallback: write a bcrypt via server on next start; leave empty here
  :
fi

cat > "$UNIT" <<'UNIT'
[Unit]
Description=Server Monitor
After=network-online.target
Wants=network-online.target

[Service]
User=servermon
Group=servermon
WorkingDirectory=/var/lib/server-monitor
ExecStart=/opt/server-monitor/server -config /etc/server-monitor/config.yaml
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
# Open firewall port 8888 if firewalld is present
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --add-port=8888/tcp --permanent || true
  firewall-cmd --reload || true
fi
# If docker group exists, add servermon to it and set SupplementaryGroups in unit
if getent group docker >/dev/null 2>&1; then
  usermod -aG docker servermon || true
  if ! grep -q '^SupplementaryGroups=docker' "$UNIT"; then
    sed -i '/^Group=servermon/a SupplementaryGroups=docker' "$UNIT"
  fi
  systemctl daemon-reload
fi
systemctl enable --now server-monitor
echo "Installed. Edit $CONF_DIR/config.yaml to adjust settings."


