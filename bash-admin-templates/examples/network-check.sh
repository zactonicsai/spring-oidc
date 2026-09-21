#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
PORT=""
PROCESS_PATTERN=""

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [-p PORT] [-P PROCESS_PATTERN] [-h]

Examples:
  $SCRIPT_NAME -p 8080
  $SCRIPT_NAME -p 8443 -P java
USAGE
}

while getopts ':p:P:h' opt; do
  case "$opt" in
    p) PORT="$OPTARG" ;;
    P) PROCESS_PATTERN="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) die "Option -$OPTARG requires an argument" ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done

main() {
  require_linux
  require_command ss

  echo '=== Listening TCP sockets ==='
  ss -lntp 2>/dev/null || ss -lnt

  echo
  echo '=== Listening UDP sockets ==='
  ss -lnup 2>/dev/null || ss -lnu

  if [[ -n "$PORT" ]]; then
    [[ "$PORT" =~ ^[0-9]+$ ]] || die "Port must be numeric"
    echo
    if is_port_listening "$PORT"; then
      info "Port $PORT is listening"
      ss -lntp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p "$" {print}' || true
    else
      warn "Port $PORT is NOT listening"
    fi
  fi

  if [[ -n "$PROCESS_PATTERN" ]]; then
    echo
    echo "=== Processes matching: $PROCESS_PATTERN ==="
    pgrep -a -f -- "$PROCESS_PATTERN" || warn "No matching process found"
  fi
}

main "$@"
