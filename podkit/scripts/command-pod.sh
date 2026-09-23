#!/usr/bin/env bash
# Manage the command pod. Kept for compatibility; same as `podkit command-pod <verb>`.
#   command-pod.sh deploy|ensure|grant|revoke|scale|status|shell|run|sync|destroy [args]
set -Eeuo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../bin/podkit" command-pod "$@"
