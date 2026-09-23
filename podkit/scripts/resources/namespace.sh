#!/usr/bin/env bash
# podkit resource: namespaces (created on demand by pod deploy; deleted only when podkit created them).
# shellcheck shell=bash

RESOURCE_DESC="Namespaces: create with labels, status, destroy (only podkit-created ones unless --force)"
RESOURCE_VERBS="create status destroy list"

resource_usage() {
  cat <<'USAGE'
  podkit namespace create NS [--label k=v]... [--pss baseline|restricted]   create (idempotent), labelled managed-by=podkit
  podkit namespace status NS                                                objects podkit manages in it
  podkit namespace list                                                     namespaces podkit created
  podkit namespace destroy NS [--force]                                     delete; --force also for namespaces podkit did not create
USAGE
}

namespace_exists() { kube get namespace "$1" >/dev/null 2>&1; }

# namespace_ensure NS [--label k=v]... [--pss LEVEL] -> create if missing (label it as podkit-created)
namespace_ensure() {
  local ns=$1; shift
  local labels=("$(managed_label)") pss=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label) labels+=("$2"); shift 2 ;;
      --pss)   pss=$2; shift 2 ;;
      *) die "namespace: unknown option $1" ;;
    esac
  done
  if dry_run; then
    log "[dry-run] ensure namespace $ns exists (labels: ${labels[*]})"
  elif namespace_exists "$ns"; then
    log "namespace $ns exists"
  else
    log "creating namespace $ns"
    kube create namespace "$ns" >/dev/null
    kube label namespace "$ns" --overwrite "${labels[@]}" >/dev/null
  fi
  if [[ -n "$pss" ]]; then
    kube label namespace "$ns" --overwrite "pod-security.kubernetes.io/enforce=$pss" "pod-security.kubernetes.io/warn=$pss" >/dev/null
  fi
}

namespace_is_managed() {
  [[ "$(kube get namespace "$1" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null)" == "podkit" ]]
}

# namespace_destroy NS [force]
namespace_destroy() {
  local ns=$1 force=${2:-0}
  namespace_exists "$ns" || { log "namespace $ns does not exist"; return 0; }
  if ! dry_run && ! namespace_is_managed "$ns" && [[ "$force" != "1" ]]; then
    die "namespace $ns was not created by podkit; use --force to delete it anyway"
  fi
  confirm "Delete namespace $ns and everything in it?" || return 0
  kube delete namespace "$ns" --ignore-not-found --wait=true
  log "deleted namespace $ns"
}

cmd_create() { [[ -n "${1:-}" ]] || die "usage: podkit namespace create NS [--label k=v] [--pss LEVEL]"; namespace_ensure "$@"; }
cmd_status() {
  local ns=${1:?usage: podkit namespace status NS}
  kube get namespace "$ns" --show-labels
  echo; kube -n "$ns" get deploy,svc,sa,cm,secret,netpol,hpa -l "$(managed_label)" 2>/dev/null || true
}
cmd_list() { kube get namespaces -l "$(managed_label)"; }
cmd_destroy() {
  local ns="" force=0 a
  for a in "$@"; do case "$a" in --force) force=1 ;; *) ns=$a ;; esac; done
  [[ -n "$ns" ]] || die "usage: podkit namespace destroy NS [--force]"
  namespace_destroy "$ns" "$force"
}
