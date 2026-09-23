#!/usr/bin/env bash
# Destroy a generated pod build (build/<provider>/<name>). Kept for compatibility; same as `podkit pod destroy`.
#   destroy.sh [-m kubectl|terraform] [-y] BUILD_DIR      (podkit destroy BUILD_DIR --everything tears down all dependent resources)
set -Eeuo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../bin/podkit" pod destroy "$@"
