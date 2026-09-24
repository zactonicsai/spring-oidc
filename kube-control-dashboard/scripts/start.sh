#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v node >/dev/null 2>&1 || { echo "ERROR: node is required (20+ recommended)." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is required." >&2; exit 1; }


echo "Current context: $(kubectl config current-context 2>/dev/null || echo none)"
echo "Starting dashboard at http://${HOST:-127.0.0.1}:${PORT:-8787}"
exec npm start
