#!/usr/bin/env bash
# podkit resource: what podkit currently runs in the cluster.
# shellcheck shell=bash

RESOURCE_DESC="Overview of everything podkit manages in the current cluster"
RESOURCE_VERBS="show"

resource_usage() {
  cat <<'USAGE'
  podkit status [NS]         command pod, workloads, Secrets and TLS material (all namespaces or one)
USAGE
}

status_show() {
  local ns=${1:-} scope=(-A)
  [[ -n "$ns" ]] && scope=(-n "$ns")
  require_cmd kubectl
  echo "context : $(current_context)"
  echo
  plugin_source command-pod
  echo "== command pod (namespace $COMMAND_POD_NS)"; commandpod_status 2>/dev/null || true
  echo; echo "== workloads"; kube get deployments "${scope[@]}" -l "$(managed_label)" -o wide 2>/dev/null || true
  echo; echo "== services"; kube get services "${scope[@]}" -l "$(managed_label)" 2>/dev/null || true
  echo; echo "== secrets"; kube get secrets "${scope[@]}" -l "$(managed_label)" 2>/dev/null || true
  echo; echo "== network policies"; kube get networkpolicies "${scope[@]}" -l "$(managed_label)" 2>/dev/null || true
}

cmd_show()     { status_show "$@"; }
cmd__default() { status_show "$@"; }
