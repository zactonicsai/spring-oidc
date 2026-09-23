#!/usr/bin/env bash
# podkit resource: orchestrated teardown — one build with its dependent resources, or everything
# podkit created in the cluster. Every step honours -y (no prompts) and --dry-run (print only).
# shellcheck shell=bash

RESOURCE_DESC="Teardown: a build with its secrets/TLS/identity/namespace, or everything podkit created"
RESOURCE_VERBS="build all plan"

resource_usage() {
  cat <<'USAGE'
  podkit destroy BUILD_DIR [options]          (same as: podkit destroy build BUILD_DIR)
      -m kubectl|terraform   how the workload was deployed (default kubectl)
      --tls                  also delete the pod's keystore Secret
      --ca                   also delete the namespace's shared CA + truststore (implies --tls)
      --identity             also destroy the cloud identity (Terraform module.cloud)
      --namespace            also delete the namespace (only if podkit created it)
      --everything           all of the above
  podkit destroy all [options]                everything labelled app.kubernetes.io/managed-by=podkit
      --builds DIR           also `terraform destroy` every build under DIR that has Terraform state
      --command-pod          also remove the command pod
      --namespaces           also delete namespaces podkit created
  podkit destroy plan BUILD_DIR|all [...]     dry-run of the above (same as --dry-run)
  Order for a build: workload + env Secret -> TLS Secrets -> cloud identity -> namespace.
USAGE
}

# destroy_build BUILD_DIR [flags...]
destroy_build() {
  local dir=$1; shift
  local mode="kubectl" tls=0 ca=0 identity=0 ns=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--mode) mode=$2; shift 2 ;;
      --tls) tls=1; shift ;;
      --ca) tls=1; ca=1; shift ;;
      --identity) identity=1; shift ;;
      --namespace) ns=1; shift ;;
      --everything) tls=1; ca=1; identity=1; ns=1; shift ;;
      *) die "destroy: unknown option $1" ;;
    esac
  done
  build_load "$dir"
  plugin_source pod tls identity namespace
  local plan="workload + env Secret"
  [[ $tls == 1 ]] && plan+=", keystore Secret"
  [[ $ca == 1 ]] && plan+=", CA + truststore"
  [[ $identity == 1 ]] && plan+=", cloud identity"
  [[ $ns == 1 ]] && plan+=", namespace $NAMESPACE"
  log "teardown plan for $NAME ($NAMESPACE, $mode): $plan"
  confirm "Proceed?" || return 0
  export PODKIT_YES=1   # one confirmation for the whole plan
  if [[ "$mode" == "terraform" ]]; then
    pod_destroy_terraform "$BUILD_DIR"          # workload + identity together
  else
    pod_destroy_kubectl "$BUILD_DIR" 0 0
  fi
  if [[ "$tls" == "1" && "${TLS_ENABLED:-false}" == "true" ]]; then
    tls_destroy "$NAMESPACE" "$TLS_KEYSTORE_SECRET" "$ca" "$TLS_CA_SECRET" "$TLS_TRUSTSTORE_SECRET"
  fi
  if [[ "$identity" == "1" && "$mode" != "terraform" && "${IDENTITY_ENABLED:-false}" == "true" ]]; then
    if [[ -d "$BUILD_DIR/terraform/.terraform" ]] || dry_run; then
      identity_destroy_build "$BUILD_DIR"
    else
      warn "no Terraform state in $BUILD_DIR/terraform; identity not managed here"
    fi
  fi
  if [[ "$ns" == "1" ]]; then
    namespace_destroy "$NAMESPACE" 0 || warn "namespace $NAMESPACE kept"
  fi
  log "teardown of $NAME finished"
}

# destroy_all [--builds DIR] [--command-pod] [--namespaces]
destroy_all() {
  local builds="" cpod=0 nss=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --builds) builds=$2; shift 2 ;;
      --command-pod) cpod=1; shift ;;
      --namespaces) nss=1; shift ;;
      *) die "destroy all: unknown option $1" ;;
    esac
  done
  plugin_source pod command-pod namespace
  require_cmd kubectl
  echo "podkit objects in the cluster (context: $(current_context)):"
  kube get deploy,hpa,netpol,svc,sa,cm,secret -A -l "$(managed_label)" 2>/dev/null || true
  confirm "Delete ALL of the above${cpod:+ + command pod}$([[ $nss == 1 ]] && echo ' + podkit namespaces')?" || return 0
  export PODKIT_YES=1
  local b
  if [[ -n "$builds" ]]; then
    for b in "$builds"/*/*/; do
      [[ -f "$b/pod.env" ]] || continue
      if [[ -d "$b/terraform/.terraform" ]]; then
        log "terraform destroy: $b"
        pod_destroy_terraform "$b"
      else
        log "skipping $b (no Terraform state)"
      fi
    done
  fi
  log "deleting every podkit-labelled object in all namespaces"
  kube delete deploy,hpa,netpol,svc,sa,cm,secret -A -l "$(managed_label)" --ignore-not-found --wait=true
  [[ "$cpod" == "1" ]] && commandpod_destroy
  if [[ "$nss" == "1" ]]; then
    for ns in $(kube get namespaces -l "$(managed_label)" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
      namespace_destroy "$ns" 0
    done
  fi
  log "podkit footprint removed"
}

cmd_build()    { [[ -n "${1:-}" ]] || die "usage: podkit destroy build BUILD_DIR [options]"; destroy_build "$@"; }
cmd_all()      { destroy_all "$@"; }
cmd_plan()     { export PODKIT_DRY_RUN=1; cmd__default "$@"; }
cmd__default() {
  case "${1:-}" in
    all) shift; destroy_all "$@" ;;
    --all) shift; destroy_all "$@" ;;
    "") plugin_usage; exit 1 ;;
    *) destroy_build "$@" ;;
  esac
}
