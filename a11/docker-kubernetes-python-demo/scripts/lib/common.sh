#!/usr/bin/env bash
# Shared helpers for every script in scripts/ and scripts/azure/.
# Usage (at the top of a script):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"      # from scripts/
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"   # from scripts/azure/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$ROOT/build"
CONFIG_FILE="${APP_CONFIG:-$ROOT/app.config.yaml}"

# ---------- pretty output ----------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✖ %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- tool checks ----------
require() {           # require docker kind kubectl ...
  local missing=()
  for cmd in "$@"; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
  [[ ${#missing[@]} -eq 0 ]] || die "missing tool(s): ${missing[*]}  (see docs/08-troubleshooting.md)"
}

# ---------- config ----------
# Render app.config.yaml -> build/config.env (+ helm values etc.) and load the variables.
# Pass --registry <host> to prefix images with a registry (Azure scripts do this).
load_config() {
  require python3
  python3 -c 'import yaml' 2>/dev/null || die "python module 'yaml' missing: pip install -r tools/requirements.txt"
  python3 "$ROOT/tools/appconfig.py" validate -c "$CONFIG_FILE" >/dev/null || die "app.config.yaml is invalid (run: make validate)"
  python3 "$ROOT/tools/appconfig.py" render all -c "$CONFIG_FILE" -o "$BUILD_DIR" "$@" >/dev/null
  # shellcheck disable=SC1091
  source "$BUILD_DIR/config.env"
  # optional per-machine overrides (git-ignored)
  if [[ -f "$ROOT/.env" ]]; then set -a; # shellcheck disable=SC1091
    source "$ROOT/.env"; set +a; fi
  export ROOT BUILD_DIR APP_NAME APP_VERSION APP_NAMESPACE
}

# Read a value from the resolved config: cfg services.0.image.full
cfg() { python3 "$ROOT/tools/appconfig.py" get "$1" -c "$CONFIG_FILE"; }

# Per-service variable lookup: svc_var web IMAGE  -> $SERVICE_WEB_IMAGE
svc_var() { local n; n="$(echo "$1" | tr '[:lower:]-' '[:upper:]_')"; local v="SERVICE_${n}_$2"; printf '%s' "${!v}"; }

# ---------- helm ----------
helm_values_args() {  # echo the -f flags for helm (secrets file only if it has content)
  local args=(-f "$BUILD_DIR/helm-values.yaml")
  [[ -s "$BUILD_DIR/secrets-values.yaml" ]] && args+=(-f "$BUILD_DIR/secrets-values.yaml")
  printf '%s\n' "${args[@]}"
}

# ---------- waiting ----------
wait_for_rollout() {  # wait_for_rollout <namespace> <deployment> [timeout]
  kubectl -n "$1" rollout status "deployment/$2" --timeout="${3:-180s}"
}
