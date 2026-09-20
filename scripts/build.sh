#!/usr/bin/env bash
set -euo pipefail

if ! command -v mvn >/dev/null 2>&1; then
  echo "ERROR: Maven is not installed or not on PATH." >&2
  echo "Install Maven 3.9+ and try again." >&2
  exit 1
fi

mvn clean verify
