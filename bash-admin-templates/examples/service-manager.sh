#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
ACTION="status"
SERVICE=""
FOLLOW_LOGS=0

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME -s SERVICE [-a ACTION] [-f] [-h]

Options:
  -s SERVICE  systemd unit name, e.g. sshd.service
  -a ACTION   status|start|stop|restart|enable|disable (default: status)
  -f          Follow journal after action
  -h          Help
USAGE
}

while getopts ':s:a:fh' opt; do
  case "$opt" in
    s) SERVICE="$OPTARG" ;;
    a) ACTION="$OPTARG" ;;
    f) FOLLOW_LOGS=1 ;;
    h) usage; exit 0 ;;
    :) die "Option -$OPTARG requires an argument" ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done

main() {
  require_linux
  require_command systemctl
  require_command journalctl
  [[ -n "$SERVICE" ]] || { usage; die "-s SERVICE is required"; }

  case "$ACTION" in
    status)
      systemctl --no-pager --full status "$SERVICE" || true
      ;;
    start|stop|restart|enable|disable)
      require_root
      systemctl "$ACTION" "$SERVICE"
      ;;
    *) die "Unsupported action: $ACTION" ;;
  esac

  printf '\nActive : %s\n' "$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
  printf 'Enabled: %s\n' "$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

  if (( FOLLOW_LOGS )); then
    journalctl -u "$SERVICE" -f
  else
    printf '\nRecent logs:\n'
    journalctl -u "$SERVICE" -n 20 --no-pager || true
  fi
}

main "$@"
