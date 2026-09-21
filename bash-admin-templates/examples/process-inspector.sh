#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
PID=""
NAME=""

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [-p PID | -n PROCESS_NAME] [-h]

Shows process information using ps, /proc, pgrep, and open network sockets.
USAGE
}

while getopts ':p:n:h' opt; do
  case "$opt" in
    p) PID="$OPTARG" ;;
    n) NAME="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) die "Option -$OPTARG requires an argument" ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done

inspect_pid() {
  local pid="$1"
  pid_is_running "$pid" || die "PID $pid is not running"

  echo "=== Process summary ==="
  ps -p "$pid" -o pid,ppid,user,%cpu,%mem,etimes,lstart,stat,args

  if [[ -r "/proc/$pid/status" ]]; then
    echo
    echo "=== /proc/$pid/status highlights ==="
    grep -E '^(Name|State|Pid|PPid|Threads|VmRSS|VmSize|FDSize):' "/proc/$pid/status" || true
  fi

  if [[ -d "/proc/$pid/fd" ]]; then
    echo
    echo "Open file descriptors: $(find "/proc/$pid/fd" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')"
  fi

  if command_exists ss; then
    echo
    echo "=== Network sockets owned by PID $pid ==="
    ss -lntup 2>/dev/null | grep -E "pid=$pid([,)]|$)" || echo "No matching listening sockets found or permissions are limited."
  fi
}

main() {
  require_linux
  require_command ps

  if [[ -n "$NAME" ]]; then
    require_command pgrep
    mapfile -t pids < <(pgrep -f -- "$NAME" || true)
    ((${#pids[@]} > 0)) || die "No process matches: $NAME"
    printf 'Matching PIDs: %s\n' "${pids[*]}"
    PID="${pids[0]}"
    ((${#pids[@]} > 1)) && warn "Multiple matches; inspecting first PID: $PID"
  fi

  [[ -n "$PID" ]] || { usage; die "Supply -p PID or -n PROCESS_NAME"; }
  [[ "$PID" =~ ^[0-9]+$ ]] || die "PID must be numeric"
  inspect_pid "$PID"
}

main "$@"
