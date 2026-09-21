#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

readonly SCRIPT_NAME="$(basename "$0")"
VERBOSE=0
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [-v] [-n] [-h]

Options:
  -v  Verbose output
  -n  Dry run; show actions without changing the system
  -h  Show help
USAGE
}

cleanup() {
  local exit_code=$?
  # Put temporary-file cleanup here.
  if (( exit_code != 0 )); then
    error "$SCRIPT_NAME failed with exit code $exit_code"
  fi
}
trap cleanup EXIT
trap 'error "Failure near line $LINENO: $BASH_COMMAND"' ERR
trap 'warn "Interrupted"; exit 130' INT TERM

run() {
  if (( DRY_RUN )); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

while getopts ':vnh' opt; do
  case "$opt" in
    v) VERBOSE=1 ;;
    n) DRY_RUN=1 ;;
    h) usage; exit 0 ;;
    :) die "Option -$OPTARG requires an argument" ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

main() {
  info "Starting $SCRIPT_NAME"
  (( VERBOSE )) && info "Verbose mode enabled"
  (( DRY_RUN )) && info "Dry-run mode enabled"

  # Example action:
  run printf '%s\n' "Template is working."

  info "Completed successfully"
}

main "$@"
