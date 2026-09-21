#!/usr/bin/env bash
# Shared helper functions for administrative Bash scripts.

# Do not enable shell options here; let the calling script decide.

log() {
  local level="$1"; shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

info()  { log INFO "$@"; }
warn()  { log WARN "$@"; }
error() { log ERROR "$@"; }
die()   { error "$@"; exit 1; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  command_exists "$1" || die "Required command not found: $1"
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "This operation must be run as root."
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "This script requires Linux."
}

confirm() {
  local prompt="${1:-Continue?}"
  local reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

is_port_listening() {
  local port="$1"
  require_command ss
  ss -lntH | awk '{print $4}' | grep -Eq "(^|:)$port$"
}

service_is_active() {
  local service="$1"
  require_command systemctl
  systemctl is-active --quiet "$service"
}

service_is_enabled() {
  local service="$1"
  require_command systemctl
  systemctl is-enabled --quiet "$service"
}

pid_is_running() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

human_duration() {
  local total="$1"
  printf '%02dh:%02dm:%02ds\n' "$((total/3600))" "$(((total%3600)/60))" "$((total%60))"
}
