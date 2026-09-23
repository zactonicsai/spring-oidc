#!/usr/bin/env bash
# Shared helpers for podkit scripts and resource plugins. Source it; do not execute it.
# shellcheck shell=bash

if [[ -n "${_PODKIT_COMMON_LOADED:-}" ]]; then return 0; fi
_PODKIT_COMMON_LOADED=1

PODKIT_ROOT="${PODKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export PODKIT_ROOT

log()  { printf '\033[1;34m[podkit]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[podkit] warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[podkit] error:\033[0m %s\n' "$*" >&2; exit 1; }

# dry_run -> true when PODKIT_DRY_RUN=1 (podkit --dry-run): mutating commands are printed, not run
dry_run() { [[ "${PODKIT_DRY_RUN:-0}" == "1" ]]; }

# require_cmd kubectl aws ... -> fail early with a clear message
require_cmd() {
  local c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      if dry_run; then warn "command not found: $c (ignored in dry-run)"; else die "required command not found: $c"; fi
    fi
  done
}

# confirm "question" -> true if the user says yes (or PODKIT_YES=1 / podkit -y); always true in dry-run
confirm() {
  [[ "${PODKIT_YES:-0}" == "1" ]] && return 0
  dry_run && return 0
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# run CMD ARGS... -> run a command, or print it in dry-run mode
run() {
  if dry_run; then printf '[dry-run] %s\n' "$*" >&2; return 0; fi
  "$@"
}

# kube ... -> kubectl honouring KUBE_CONTEXT. In dry-run mode every call is printed instead
# (reads return nothing), so `podkit --dry-run ...` shows exactly what would happen.
kube() {
  if dry_run; then
    printf '[dry-run] kubectl%s %s\n' "${KUBE_CONTEXT:+ --context $KUBE_CONTEXT}" "$*" >&2
    # drain piped manifests (`... | kube apply -f -`) so the writer never gets SIGPIPE
    local a prev=""
    for a in "$@"; do
      if [[ "$a" == "-f-" || "$a" == "--filename=-" || "$a" == "-i" || "$a" == "--stdin" || ( "$prev" == "-f" && "$a" == "-" ) ]]; then
        cat >/dev/null; break
      fi
      prev=$a
    done
    return 0
  fi
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl --context "$KUBE_CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

current_context() { dry_run && { echo "dry-run"; return; }; kube config current-context 2>/dev/null || echo "none"; }

# terraform_bin -> terraform or tofu (TERRAFORM_BIN overrides)
terraform_bin() {
  if [[ -n "${TERRAFORM_BIN:-}" ]]; then echo "$TERRAFORM_BIN"; return; fi
  command -v terraform 2>/dev/null || command -v tofu 2>/dev/null || die "terraform (or tofu) is not installed"
}

# tf DIR ARGS... -> run terraform in DIR (printed in dry-run mode)
tf() {
  local dir=$1; shift
  if dry_run; then printf '[dry-run] (cd %s && terraform %s)\n' "$dir" "$*" >&2; return 0; fi
  (cd "$dir" && "$(terraform_bin)" "$@")
}

# load_env_file FILE -> export every KEY=VALUE in FILE (values may reference ${VARS} already set)
load_env_file() {
  [[ -f "$1" ]] || die "env file not found: $1"
  set -a
  # shellcheck source=/dev/null
  source "$1"
  set +a
}

# build_load BUILD_DIR -> validate a generated build directory and export its pod.env (+ BUILD_DIR)
build_load() {
  local dir=${1:-}
  [[ -n "$dir" ]] || die "a build directory is required (build/<cloud>/<name>)"
  [[ -f "$dir/pod.env" ]] || die "not a podkit build directory (no pod.env): $dir"
  BUILD_DIR="$(cd "$dir" && pwd)"
  export BUILD_DIR
  load_env_file "$BUILD_DIR/pod.env"
}

# provider_title aws -> "AWS (EKS)"
provider_title() {
  case "$1" in
    aws) echo "AWS (EKS)" ;; azure) echo "Azure (AKS)" ;; gcp) echo "Google Cloud (GKE)" ;; *) echo "$1" ;;
  esac
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

# set_env_value FILE KEY VALUE -> replace (or append) KEY=... in a KEY=VALUE file
set_env_value() {
  local file=$1 key=$2 value=$3 tmp
  tmp="$(mktemp)"
  if grep -q "^$key=" "$file"; then
    awk -v k="$key" -v v="$value" 'index($0, k"=")==1 {print k"="v; next} {print}' "$file" > "$tmp"
  else
    { cat "$file"; printf '%s=%s\n' "$key" "$value"; } > "$tmp"
  fi
  cat "$tmp" > "$file" && rm -f "$tmp"
}

# managed_label -> selector for everything podkit creates
managed_label() { echo "app.kubernetes.io/managed-by=podkit"; }
