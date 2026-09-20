#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

JAR="target/spring-oidc-cli-0.1.0.jar"
if [[ ! -f "$JAR" ]]; then
  echo "ERROR: $JAR not found. Run ./scripts/build.sh first." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  set -- login
fi

exec java -jar "$JAR" "$@"
