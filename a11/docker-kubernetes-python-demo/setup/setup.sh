#!/usr/bin/env bash
# =============================================================================
# setup.sh — FIRST script that runs on a fresh base Linux host (Ubuntu/Debian).
#
# Runs on:  an Azure VM (via cloud-init)    -> /opt/<app>/setup.sh
#           a local docker "host" container -> terraform/local-docker
#           any Ubuntu box you copy it to   -> sudo ./setup.sh
#
# Reads host-config.env (rendered from app.config.yaml) from the same folder.
# It is IDEMPOTENT: safe to run again; it only changes what is missing.
#
# What it does:   1. install packages    2. install Docker Engine (or CLI)
#                 3. firewall (ufw) from hosts.exposePorts   4. admin user + docker group
#                 5. timezone            6. leave a marker so configure.sh knows setup ran
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HOST_CONFIG:-$HERE/host-config.env}"
[[ -f "$CONFIG" ]] || { echo "missing $CONFIG (render it with: tools/appconfig.py render host)"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"
: "${APP_NAME:?}" "${ADMIN_USER:=azureuser}" "${PACKAGES:=curl ca-certificates}" "${EXPOSE_PORTS:=}"

log() { printf '\n[setup %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[[ $EUID -eq 0 ]] || { echo "run as root (sudo $0)"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

in_container() { [[ -f /.dockerenv ]] || grep -qE '(docker|containerd|lxc)' /proc/1/cgroup 2>/dev/null; }
has_systemd()  { [[ -d /run/systemd/system ]]; }

# ---- 1. packages --------------------------------------------------------------
log "installing packages: $PACKAGES"
apt-get update -q
# shellcheck disable=SC2086
apt-get install -y -q $PACKAGES

# ---- 2. docker ------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  log "docker already installed: $(docker --version)"
else
  log "installing Docker Engine from Docker's official apt repository"
  install -m 0755 -d /etc/apt/keyrings
  . /etc/os-release
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  if in_container; then
    apt-get install -y -q docker-ce-cli            # a container cannot run its own daemon: CLI only
  else
    apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    has_systemd && systemctl enable --now docker
  fi
fi

# ---- 3. firewall ----------------------------------------------------------------
if in_container; then
  log "container detected: skipping ufw (no NET_ADMIN); Azure NSG / docker port mapping controls access instead"
elif command -v ufw >/dev/null 2>&1; then
  log "configuring ufw: default deny incoming, allow: ${EXPOSE_PORTS:-none}"
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  for p in $EXPOSE_PORTS; do ufw allow "$p" >/dev/null; done
  ufw --force enable
  ufw status numbered
fi

# ---- 4. admin user ----------------------------------------------------------------
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
  log "creating user $ADMIN_USER"
  useradd -m -s /bin/bash "$ADMIN_USER"
fi
getent group docker >/dev/null && usermod -aG docker "$ADMIN_USER" || true

# ---- 5. timezone ------------------------------------------------------------------
if [[ -n "${SETTING_TIMEZONE:-}" ]]; then
  log "timezone -> $SETTING_TIMEZONE"
  if has_systemd && command -v timedatectl >/dev/null; then timedatectl set-timezone "$SETTING_TIMEZONE" || true
  elif [[ -f "/usr/share/zoneinfo/$SETTING_TIMEZONE" ]]; then ln -sf "/usr/share/zoneinfo/$SETTING_TIMEZONE" /etc/localtime; fi
fi

# ---- 6. marker --------------------------------------------------------------------
mkdir -p "/etc/$APP_NAME" "/var/lib/$APP_NAME"
date -u +%FT%TZ > "/var/lib/$APP_NAME/setup.done"
log "setup complete for $APP_NAME v${APP_VERSION:-?} — next: configure.sh"
