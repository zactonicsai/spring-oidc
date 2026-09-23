#!/usr/bin/env bash
# Template for a podkit resource plugin. Copy to scripts/resources/<name>.sh (or plugins/<name>.sh,
# or ~/.podkit/plugins/<name>.sh) and it appears in `podkit resources` immediately.
# Rules: only define variables and functions here (no side effects), keep library functions
# prefixed with <name>_ so other plugins can `plugin_source <name>` and reuse them.
# shellcheck shell=bash

RESOURCE_DESC="What this resource is, in one line"
RESOURCE_VERBS="deploy status destroy"

resource_usage() {
  cat <<'USAGE'
  podkit example deploy BUILD_DIR       create or update the thing
  podkit example status BUILD_DIR       show it
  podkit example destroy BUILD_DIR      remove it (honours -y and --dry-run)
USAGE
}

# ---- library (reusable) -----------------------------------------------------------------------
example_deploy() { build_load "$1"; log "deploying example for $NAME in $NAMESPACE"; kube -n "$NAMESPACE" get pods; }
example_status() { build_load "$1"; kube -n "$NAMESPACE" get pods -l "app.kubernetes.io/name=$NAME"; }
example_destroy() { build_load "$1"; confirm "Remove example for $NAME?" || return 0; kube -n "$NAMESPACE" delete pod -l "app.kubernetes.io/name=$NAME" --ignore-not-found; }

# ---- CLI verbs ----------------------------------------------------------------------------------
cmd_deploy()  { example_deploy "${1:-}"; }
cmd_status()  { example_status "${1:-}"; }
cmd_destroy() { example_destroy "${1:-}"; }
