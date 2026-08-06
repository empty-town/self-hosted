#!/usr/bin/env bash
# One-time host preparation. Run as root or with sudo.
# 1. Creates the Docker networks (segmented by trust level).
# 2. Generates secrets into .env if they are empty.
# 3. Blocks Docker bridge subnets from the LAN (DOCKER-USER chain).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
LAN_SUBNET="${LAN_SUBNET:-192.168.1.0/24}"   # CHANGE to your LAN range

# --- 1. Networks -------------------------------------------------------------
# Two networks per stack: a caddy-facing net (caddy + the app) and an internal
# net (app + database/cache/helpers) that caddy is NOT attached to. A popped
# caddy can reach only the app containers, never a DB or Redis port.
# The internal nets are ordinary bridges (not --internal): the *arr apps and
# Immich ML need outbound internet, and backends still publish no ports.
#
# nextcloud_net gets a pinned subnet so Nextcloud's TRUSTED_PROXIES can name
# it exactly. Change it here AND in stacks/nextcloud/docker-compose.yml if it
# collides with a range you already use.
docker network inspect nextcloud_net >/dev/null 2>&1 \
  || docker network create --subnet 172.30.30.0/24 nextcloud_net
for net in frontend media_net immich_net \
           media_internal immich_internal nextcloud_internal; do
  docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net"
done
echo "[ok] networks"

# --- 2. Secrets --------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$REPO_DIR/.env.example" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

gen() { openssl rand -hex 32; }

fill() {  # fill KEY if empty
  local key="$1" val="$2"
  if grep -qE "^${key}=$" "$ENV_FILE"; then
    sed -i "s|^${key}=$|${key}=${val}|" "$ENV_FILE"
    echo "[ok] generated ${key}"
  fi
}

fill CROWDSEC_API_KEY "$(gen)"
fill IMMICH_DB_PASSWORD "$(gen)"
fill NC_DB_PASSWORD "$(gen)"
fill NC_DB_ROOT_PASSWORD "$(gen)"
echo "[!!] Set DOMAIN and TZ in .env manually. They are not generated."
echo "     Set CF_API_TOKEN only if you turn on the optional ddns service."

# --- 3. Block Docker bridges from the LAN ------------------------------------
# Docker inserts its rules below ufw/firewalld. Use the DOCKER-USER chain,
# which Docker respects and evaluates first.
# Rules must be INSERTED (-I) above Docker's terminal RETURN rule — an
# appended (-A) rule lands after RETURN and never fires. Insert DROP first,
# then insert ACCEPT above it: final order is ACCEPT, DROP, RETURN.
iptables -C DOCKER-USER -d "$LAN_SUBNET" -j DROP 2>/dev/null \
  || iptables -I DOCKER-USER -d "$LAN_SUBNET" -j DROP
iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
echo "[ok] DOCKER-USER rules: containers cannot reach $LAN_SUBNET"

# Docker recreates DOCKER-USER empty on every reboot, so install a systemd
# unit that re-applies the rules after docker starts. (Do NOT use
# iptables-persistent with Docker; it bakes in stale Docker rules.)
cat > /etc/systemd/system/docker-user-lan-block.service <<EOF
[Unit]
Description=Re-apply DOCKER-USER LAN block after Docker starts
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'iptables -C DOCKER-USER -d ${LAN_SUBNET} -j DROP 2>/dev/null || iptables -I DOCKER-USER -d ${LAN_SUBNET} -j DROP'
ExecStart=/bin/sh -c 'iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable docker-user-lan-block.service >/dev/null 2>&1
echo "[ok] docker-user-lan-block.service installed (re-applies the rules on boot)"

echo
echo "Manual steps that remain:"
echo "  1. Router: forward 80 and 443 to this host."
echo "  2. Router: disable UPnP."
echo "  3. DNS: add one A record per service (jellyfin, photos, cloud) -> your public IP."
echo "     Avoid a wildcard (*) record; publish only the names you actually run."
