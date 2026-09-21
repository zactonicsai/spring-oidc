#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
SERVICE=""
PORT=""
URL=""
RESTART_ON_FAILURE=0

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME -s SERVICE [-p PORT] [-u URL] [-r] [-h]

Checks:
  1. systemd service state
  2. TCP listening port
  3. Optional HTTP/HTTPS endpoint

Options:
  -s SERVICE  systemd service name
  -p PORT     expected local listening port
  -u URL      health URL, e.g. http://127.0.0.1:8080/health
  -r          restart service if a check fails (requires root)
  -h          help
USAGE
}

while getopts ':s:p:u:rh' opt; do
  case "$opt" in
    s) SERVICE="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    u) URL="$OPTARG" ;;
    r) RESTART_ON_FAILURE=1 ;;
    h) usage; exit 0 ;;
    :) die "Option -$OPTARG requires an argument" ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done

main() {
  require_linux
  [[ -n "$SERVICE" ]] || { usage; die "-s SERVICE is required"; }

  local failed=0

  if service_is_active "$SERVICE"; then
    info "PASS service active: $SERVICE"
  else
    error "FAIL service inactive: $SERVICE"
    failed=1
  fi

  if [[ -n "$PORT" ]]; then
    [[ "$PORT" =~ ^[0-9]+$ ]] || die "Port must be numeric"
    if is_port_listening "$PORT"; then
      info "PASS port listening: $PORT"
    else
      error "FAIL port not listening: $PORT"
      failed=1
    fi
  fi

  if [[ -n "$URL" ]]; then
    require_command curl
    if curl --fail --silent --show-error --max-time 5 --output /dev/null "$URL"; then
      info "PASS URL responded successfully: $URL"
    else
      error "FAIL URL check: $URL"
      failed=1
    fi
  fi

  if (( failed && RESTART_ON_FAILURE )); then
    require_root
    warn "Restarting $SERVICE because a health check failed"
    systemctl restart "$SERVICE"
    sleep 2
    systemctl --no-pager --full status "$SERVICE" || true
  fi

  return "$failed"
}

main "$@"
