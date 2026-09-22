#!/usr/bin/env bash
# Shared helpers for podkit scripts. Source it; do not execute it.
# shellcheck shell=bash

if [[ -n "${_PODKIT_COMMON_LOADED:-}" ]]; then return 0; fi
_PODKIT_COMMON_LOADED=1

PODKIT_ROOT="${PODKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export PODKIT_ROOT

log()  { printf '\033[1;34m[podkit]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[podkit] warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[podkit] error:\033[0m %s\n' "$*" >&2; exit 1; }

# require_cmd kubectl aws ... -> fail early with a clear message
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

# confirm "question" -> true if the user says yes (or PODKIT_YES=1)
confirm() {
  [[ "${PODKIT_YES:-0}" == "1" ]] && return 0
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# kube ... -> kubectl honouring KUBE_CONTEXT
kube() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl --context "$KUBE_CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

current_context() { kube config current-context 2>/dev/null || echo "none"; }

# load_env_file FILE -> export every KEY=VALUE in FILE (values may reference ${VARS} already set)
load_env_file() {
  [[ -f "$1" ]] || die "env file not found: $1"
  set -a
  # shellcheck source=/dev/null
  source "$1"
  set +a
}

# render_template FILE KEY=VALUE... -> FILE with ${KEY} replaced (pure bash, no envsubst needed)
render_template() {
  local file=$1; shift
  local content kv key value
  content="$(<"$file")"
  for kv in "$@"; do
    key=${kv%%=*}
    value=${kv#*=}
    content=${content//"\${$key}"/"$value"}
  done
  printf '%s\n' "$content"
}

# split_csv "a,b,c" -> prints one item per line
split_csv() { tr ',' '\n' <<<"$1" | sed '/^[[:space:]]*$/d'; }
