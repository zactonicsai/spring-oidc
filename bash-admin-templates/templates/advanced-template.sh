#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'
umask 027

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME}.lock"
TMP_DIR=""
VERBOSE=0
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [-v] [-n] [-c CONFIG] [-h]

Options:
  -v          Verbose logging
  -n          Dry run
  -c CONFIG   Configuration file
  -h          Help
USAGE
}

CONFIG_FILE=""

cleanup() {
  local rc=$?
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
  (( rc == 0 )) || error "Exited with status $rc"
}
trap cleanup EXIT
trap 'error "Command failed at ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND"' ERR
trap 'warn "Received interrupt"; exit 130' INT TERM

run() {
  if (( DRY_RUN )); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

acquire_lock() {
  require_command flock
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "Another $SCRIPT_NAME process is already running."
}

load_config() {
  local file="$1"
  [[ -r "$file" ]] || die "Cannot read config file: $file"

  # Safer than sourcing arbitrary shell: accept KEY=VALUE lines only.
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key="${key//[[:space:]]/}"
    case "$key" in
      APP_NAME|APP_PORT|APP_SERVICE)
        printf -v "$key" '%s' "$value"
        export "$key"
        ;;
      *) warn "Ignoring unknown config key: $key" ;;
    esac
  done < "$file"
}

validate() {
  [[ "${APP_PORT:-}" =~ ^[0-9]+$ ]] || die "APP_PORT must be numeric"
  (( APP_PORT >= 1 && APP_PORT <= 65535 )) || die "APP_PORT out of range"
}

while getopts ':vnc:h' opt; do
  case "$opt" in
    v) VERBOSE=1 ;;
    n) DRY_RUN=1 ;;
    c) CONFIG_FILE="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) die "Option -$OPTARG requires an argument" ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

main() {
  acquire_lock
  TMP_DIR="$(mktemp -d)"

  : "${APP_NAME:=demo-app}"
  : "${APP_PORT:=8080}"
  : "${APP_SERVICE:=demo-app.service}"

  [[ -n "$CONFIG_FILE" ]] && load_config "$CONFIG_FILE"
  validate

  (( VERBOSE )) && info "Temporary directory: $TMP_DIR"
  info "Application=$APP_NAME Service=$APP_SERVICE Port=$APP_PORT"

  if service_is_active "$APP_SERVICE"; then
    info "$APP_SERVICE is active"
  else
    warn "$APP_SERVICE is not active"
  fi

  if is_port_listening "$APP_PORT"; then
    info "TCP port $APP_PORT is listening"
  else
    warn "TCP port $APP_PORT is not listening"
  fi
}

main "$@"
