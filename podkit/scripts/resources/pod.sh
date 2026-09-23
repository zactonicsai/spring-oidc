#!/usr/bin/env bash
# podkit resource: a generated pod build (build/<cloud>/<name>) — the workload itself.
# kubectl path: manifests + plugins (secret, identity, configure). Terraform path: the generated root module.
# shellcheck shell=bash

RESOURCE_DESC="Pod builds: deploy/destroy (kubectl or Terraform), status, logs, restart, scale, exec, diff"
RESOURCE_VERBS="deploy destroy status logs restart scale exec diff list"

resource_usage() {
  cat <<'USAGE'
  podkit pod deploy  BUILD_DIR [-m kubectl|terraform]                 namespace -> secrets -> ServiceAccount (+identity) -> [pre step] -> workload -> rollout -> [post step]
  podkit pod destroy BUILD_DIR [-m kubectl|terraform] [--purge-tls] [--delete-namespace]
  podkit pod status  BUILD_DIR                                        Deployment, pods, Service, recent events
  podkit pod logs    BUILD_DIR [-f] [--previous]
  podkit pod restart BUILD_DIR                                        rolling restart
  podkit pod scale   BUILD_DIR N
  podkit pod exec    BUILD_DIR -- CMD [ARGS]
  podkit pod diff    BUILD_DIR                                        server-side diff of the manifests
  podkit pod list                                                     every podkit-managed Deployment in the cluster
  ROLLOUT_TIMEOUT (300s) bounds the rollout wait.
USAGE
}

pod_selector() { echo "app.kubernetes.io/name=$NAME"; }

# pod_deploy_kubectl BUILD_DIR
pod_deploy_kubectl() {
  build_load "$1"
  plugin_source namespace secret identity configure
  require_cmd kubectl
  log "deploying $NAME to namespace $NAMESPACE on $(provider_title "$PROVIDER") (context: $(current_context))"
  namespace_ensure "$NAMESPACE"
  local checksum
  checksum="$(secret_sync_build "$BUILD_DIR")"
  kube apply --server-side --field-manager=podkit -f "$BUILD_DIR/k8s/serviceaccount.yaml" >/dev/null
  identity_bind_build "$BUILD_DIR"
  if [[ "${CONFIGURE_METHOD:-none}" != "none" && "${CONFIGURE_PHASE:-}" == "pre" ]]; then
    configure_run_build "$BUILD_DIR"
  fi
  log "applying workload manifests"
  render_template "$BUILD_DIR/k8s/workload.yaml" "SECRET_CHECKSUM=$checksum" \
    | kube apply --server-side --field-manager=podkit --force-conflicts -f -
  log "waiting for rollout"
  kube -n "$NAMESPACE" rollout status deployment/"$NAME" --timeout="${ROLLOUT_TIMEOUT:-300s}"
  if [[ "${CONFIGURE_METHOD:-none}" != "none" && "${CONFIGURE_PHASE:-}" == "post" ]]; then
    configure_run_build "$BUILD_DIR"
  fi
  log "deployed $NAME${SERVICE_DNS:+ — in-cluster address: $SERVICE_DNS}"
}

# pod_deploy_terraform BUILD_DIR
pod_deploy_terraform() {
  build_load "$1"
  plugin_source configure
  local dir="$BUILD_DIR/terraform"
  if [[ "${CONFIGURE_METHOD:-none}" != "none" && "${CONFIGURE_PHASE:-}" == "pre" ]]; then
    configure_run_build "$BUILD_DIR"
  fi
  log "terraform apply for $NAME ($(provider_title "$PROVIDER"))"
  tf "$dir" init -input=false >/dev/null
  tf "$dir" apply -input=false ${PODKIT_YES:+-auto-approve}
  if ! dry_run && [[ "${IDENTITY_ENABLED:-false}" == "true" ]]; then
    local id; id="$(tf "$dir" output -raw identity 2>/dev/null || true)"
    if [[ -n "$id" && "$id" != "null" ]]; then set_env_value "$BUILD_DIR/pod.env" IDENTITY_ID "$id"; log "identity: $id (stored in pod.env)"; fi
  fi
  if [[ "${CONFIGURE_METHOD:-none}" != "none" && "${CONFIGURE_PHASE:-}" == "post" ]]; then
    configure_run_build "$BUILD_DIR"
  fi
  log "deployed $NAME with Terraform"
}

# pod_destroy_kubectl BUILD_DIR [purge_tls] [delete_namespace]
pod_destroy_kubectl() {
  build_load "$1"
  local purge_tls=${2:-0} delete_ns=${3:-0}
  plugin_source secret tls namespace
  require_cmd kubectl
  confirm "Delete $NAME from namespace $NAMESPACE on $(provider_title "$PROVIDER") (context: $(current_context))?" || return 0
  render_template "$BUILD_DIR/k8s/workload.yaml" "SECRET_CHECKSUM=none" \
    | kube delete --ignore-not-found --wait=true -f -
  kube delete --ignore-not-found -f "$BUILD_DIR/k8s/serviceaccount.yaml"
  [[ -n "${CLOUD_SECRETS:-}" ]] && kube -n "$NAMESPACE" delete secret "$ENV_SECRET" --ignore-not-found
  if [[ "$purge_tls" == "1" && "${TLS_ENABLED:-false}" == "true" ]]; then
    kube -n "$NAMESPACE" delete secret "$TLS_KEYSTORE_SECRET" --ignore-not-found
  fi
  [[ "$delete_ns" == "1" ]] && PODKIT_YES=1 namespace_destroy "$NAMESPACE" 1
  log "destroyed $NAME"
}

# pod_destroy_terraform BUILD_DIR
pod_destroy_terraform() {
  build_load "$1"
  local dir="$BUILD_DIR/terraform"
  confirm "Destroy $NAME ($NAMESPACE) and its cloud identity with Terraform?" || return 0
  tf "$dir" init -input=false >/dev/null
  tf "$dir" destroy -input=false ${PODKIT_YES:+-auto-approve}
  # shellcheck disable=SC2016  # literal placeholder, expanded when pod.env is sourced
  dry_run || set_env_value "$BUILD_DIR/pod.env" IDENTITY_ID '${IDENTITY_ID:-}'
  log "destroyed $NAME with Terraform"
}

pod_status() {
  build_load "$1"
  echo "build     : $BUILD_DIR"
  echo "workload  : $NAMESPACE/$NAME on $(provider_title "$PROVIDER") cluster $CLUSTER_NAME"
  echo "configure : ${CONFIGURE_METHOD:-none} ${CONFIGURE_TARGET:-} (${CONFIGURE_PHASE:-})"
  echo "identity  : ${IDENTITY_ENABLED:-false} ${IDENTITY_ID:-}"
  echo
  kube -n "$NAMESPACE" get deployment "$NAME" -o wide 2>/dev/null || { echo "(not deployed)"; return 0; }
  kube -n "$NAMESPACE" get pods -l "$(pod_selector)" -o wide
  kube -n "$NAMESPACE" get service "$NAME" 2>/dev/null || true
  echo; kube -n "$NAMESPACE" get events --field-selector "involvedObject.name=$NAME" --sort-by=.lastTimestamp 2>/dev/null | tail -n 5 || true
}

# ---- argument helpers ------------------------------------------------------------------------
# pod_parse "$@" -> sets P_DIR, P_MODE, P_FLAGS (array), P_REST (array after --)
pod_parse() {
  P_DIR="" P_MODE="kubectl" P_FLAGS=() P_REST=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--mode) P_MODE=$2; shift 2 ;;
      -m=*|--mode=*) P_MODE=${1#*=}; shift ;;
      --) shift; P_REST=("$@"); break ;;
      -*) P_FLAGS+=("$1"); shift ;;
      *) [[ -z "$P_DIR" ]] && P_DIR=$1 || P_FLAGS+=("$1"); shift ;;
    esac
  done
  [[ -n "$P_DIR" ]] || die "a build directory is required (build/<cloud>/<name>)"
  [[ "$P_MODE" == "kubectl" || "$P_MODE" == "terraform" ]] || die "mode must be kubectl or terraform"
}
pod_has_flag() { local f; for f in ${P_FLAGS[@]+"${P_FLAGS[@]}"}; do [[ "$f" == "$1" ]] && return 0; done; return 1; }

cmd_deploy()  { pod_parse "$@"; if [[ "$P_MODE" == "terraform" ]]; then pod_deploy_terraform "$P_DIR"; else pod_deploy_kubectl "$P_DIR"; fi; }
cmd_destroy() {
  pod_parse "$@"
  local purge=0 delns=0
  pod_has_flag --purge-tls && purge=1
  pod_has_flag --delete-namespace && delns=1
  if [[ "$P_MODE" == "terraform" ]]; then pod_destroy_terraform "$P_DIR"; else pod_destroy_kubectl "$P_DIR" "$purge" "$delns"; fi
}
cmd_status()  { pod_status "${1:-}"; }
cmd_logs()    { pod_parse "$@"; build_load "$P_DIR"; kube -n "$NAMESPACE" logs deployment/"$NAME" --all-containers ${P_FLAGS[@]+"${P_FLAGS[@]}"}; }
cmd_restart() { build_load "${1:-}"; kube -n "$NAMESPACE" rollout restart deployment/"$NAME"; kube -n "$NAMESPACE" rollout status deployment/"$NAME" --timeout="${ROLLOUT_TIMEOUT:-300s}"; }
cmd_scale()   { build_load "${1:-}"; kube -n "$NAMESPACE" scale deployment/"$NAME" --replicas="${2:?usage: podkit pod scale BUILD_DIR N}"; }
cmd_exec()    { pod_parse "$@"; build_load "$P_DIR"; [[ ${#P_REST[@]} -gt 0 ]] || die "usage: podkit pod exec BUILD_DIR -- CMD [ARGS]"; kube -n "$NAMESPACE" exec -it deployment/"$NAME" -- "${P_REST[@]}"; }
cmd_diff()    { build_load "${1:-}"; render_template "$BUILD_DIR/k8s/workload.yaml" "SECRET_CHECKSUM=unchanged" | kube diff --server-side -f - || true; }
cmd_list()    { kube get deployments -A -l "$(managed_label)" -o wide; }
