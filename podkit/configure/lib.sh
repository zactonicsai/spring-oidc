#!/usr/bin/env bash
# Shared helpers for the shell configuration scripts (sourced; runs inside the command pod or locally).
# shellcheck shell=bash

log()  { printf '\033[1;34m[configure]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[configure] warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[configure] error:\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"; done
}

# kube ... -> kubectl honouring KUBE_CONTEXT (unset inside the command pod: in-cluster auth is used)
kube() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then kubectl --context "$KUBE_CONTEXT" "$@"; else kubectl "$@"; fi
}

secret_exists() { kube -n "$1" get secret "$2" >/dev/null 2>&1; }

# secret_key NS SECRET KEY -> decoded value (go-template handles keys with dots)
secret_key() { kube -n "$1" get secret "$2" -o go-template="{{index .data \"$3\"}}" | base64 -d; }

# running_pods NS SELECTOR -> pod names, one per line
running_pods() {
  kube -n "$1" get pods -l "$2" --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

# apply_secret NS NAME LABELS(csv) --from-file=... -> create-or-update a Secret (server-side apply)
apply_secret() {
  local ns=$1 name=$2 labels=$3; shift 3
  kube -n "$ns" create secret generic "$name" "$@" --dry-run=client -o yaml \
    | kube apply --server-side --force-conflicts --field-manager=podkit -f - >/dev/null
  # shellcheck disable=SC2086  # labels is a csv list, word splitting is intended
  [[ -n "$labels" ]] && kube -n "$ns" label secret "$name" --overwrite ${labels//,/ } >/dev/null
  return 0
}

# restart_deployments NS "a,b,c" -> rolling restart of the deployments that exist
restart_deployments() {
  local ns=$1 d stamp
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for d in ${2//,/ }; do
    if kube -n "$ns" get deployment "$d" >/dev/null 2>&1; then
      kube -n "$ns" patch deployment "$d" --type merge \
        -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"podkit.dev/restarted-at\":\"$stamp\"}}}}}" >/dev/null
      log "restarted deployment $ns/$d"
    fi
  done
}

# apply_overrides KEY=VALUE... -> export KEY=VALUE arguments, so `configure.sh ROTATE=true` works
apply_overrides() {
  local a
  for a in "$@"; do
    if [[ "$a" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then export "${a?}"; else warn "ignoring argument: $a"; fi
  done
}
