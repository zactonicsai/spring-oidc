#!/usr/bin/env bash
# Deploy a generated pod build (build/<provider>/<name>). Kept for compatibility; same as `podkit pod deploy`.
#   deploy.sh [-m kubectl|terraform] [-y] BUILD_DIR
set -Eeuo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../bin/podkit" pod deploy "$@"
