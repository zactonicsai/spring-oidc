#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

UNIT_NAME="demo-app.service"
UNIT_SOURCE="$SCRIPT_DIR/$UNIT_NAME"
UNIT_DEST="/etc/systemd/system/$UNIT_NAME"

main() {
  require_linux
  require_root
  require_command systemctl

  [[ -f "$UNIT_SOURCE" ]] || die "Unit file not found: $UNIT_SOURCE"

  install -o root -g root -m 0644 "$UNIT_SOURCE" "$UNIT_DEST"
  systemctl daemon-reload
  systemctl enable "$UNIT_NAME"

  info "Installed $UNIT_NAME"
  info "Start it with: sudo systemctl start $UNIT_NAME"
  info "View logs with: journalctl -u $UNIT_NAME -f"
}

main "$@"
