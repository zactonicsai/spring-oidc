#!/usr/bin/env bash
# Manage the in-cluster command pod (the place where configuration steps run).
#
#   command-pod.sh deploy              create/update namespace, ServiceAccount, RBAC and Deployment, wait until ready
#   command-pod.sh ensure              deploy if missing, scale up if idle, wait until ready (idempotent)
#   command-pod.sh grant NS [NS...]    allow the command pod to configure more namespaces (namespaced RBAC)
#   command-pod.sh scale N             scale the Deployment (0 = idle, costs nothing)
#   command-pod.sh status              show pod, image and granted namespaces
#   command-pod.sh shell               interactive shell inside the pod
#   command-pod.sh run -- CMD [ARGS]   run a command inside the pod
#   command-pod.sh sync SRC_DIR DEST   copy a local directory into the pod (tar over kubectl exec)
#   command-pod.sh destroy             delete the Deployment, RBAC and ServiceAccount (DELETE_NAMESPACE=1 also removes the namespace)
#
# Environment: COMMAND_POD_NS (default ops), COMMAND_POD_IMAGE, TARGET_NAMESPACES (comma separated),
#              KUBE_CONTEXT, PODKIT_YES=1 to skip confirmations.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

COMMAND_POD_NS="${COMMAND_POD_NS:-ops}"
COMMAND_POD_IMAGE="${COMMAND_POD_IMAGE:-ghcr.io/your-org/podkit-command-pod:latest}"
TARGET_NAMESPACES="${TARGET_NAMESPACES:-default}"
SELECTOR="app.kubernetes.io/name=command-pod"
MANIFESTS="$PODKIT_ROOT/command-pod/k8s"
WAIT_TIMEOUT="${COMMAND_POD_WAIT:-180s}"

usage() { sed -n '2,17p' "${BASH_SOURCE[0]}"; }

pod_name() {
  kube -n "$COMMAND_POD_NS" get pod -l "$SELECTOR" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

exists() { kube -n "$COMMAND_POD_NS" get deployment command-pod >/dev/null 2>&1; }

apply_rbac() {
  local ns
  for ns in "$@"; do
    [[ -n "$ns" ]] || continue
    kube get namespace "$ns" >/dev/null 2>&1 || kube create namespace "$ns"
    render_template "$MANIFESTS/rbac.yaml" "TARGET_NAMESPACE=$ns" "COMMAND_POD_NS=$COMMAND_POD_NS" \
      | kube apply --server-side --field-manager=podkit -f - >/dev/null
    log "command pod may configure namespace '$ns'"
  done
}

wait_ready() {
  log "Waiting for the command pod to be ready"
  kube -n "$COMMAND_POD_NS" rollout status deployment/command-pod --timeout="$WAIT_TIMEOUT"
}

cmd_deploy() {
  require_cmd kubectl
  local replicas="${1:-1}"
  log "Deploying command pod to namespace $COMMAND_POD_NS (image: $COMMAND_POD_IMAGE)"
  render_template "$MANIFESTS/command-pod.yaml" "COMMAND_POD_NS=$COMMAND_POD_NS" \
    "COMMAND_POD_IMAGE=$COMMAND_POD_IMAGE" "REPLICAS=$replicas" \
    | kube apply --server-side --field-manager=podkit -f -
  mapfile -t namespaces < <(split_csv "$TARGET_NAMESPACES")
  apply_rbac "${namespaces[@]}"
  [[ "$replicas" -gt 0 ]] && wait_ready
  return 0
}

cmd_ensure() {
  require_cmd kubectl
  if ! exists; then
    cmd_deploy 1
    return
  fi
  mapfile -t namespaces < <(split_csv "$TARGET_NAMESPACES")
  apply_rbac "${namespaces[@]}"
  local replicas
  replicas="$(kube -n "$COMMAND_POD_NS" get deployment command-pod -o jsonpath='{.spec.replicas}')"
  if [[ "${replicas:-0}" -lt 1 ]]; then
    log "Command pod is idle; scaling to 1"
    kube -n "$COMMAND_POD_NS" scale deployment/command-pod --replicas=1 >/dev/null
  fi
  wait_ready
}

cmd_scale() {
  local n="${1:?usage: command-pod.sh scale N}"
  kube -n "$COMMAND_POD_NS" scale deployment/command-pod --replicas="$n"
  log "command pod scaled to $n replica(s)"
}

cmd_status() {
  exists || { log "command pod is not deployed in namespace $COMMAND_POD_NS"; return 0; }
  kube -n "$COMMAND_POD_NS" get deployment command-pod -o wide
  kube -n "$COMMAND_POD_NS" get pod -l "$SELECTOR" -o wide
  log "granted namespaces:"
  kube get rolebinding -A -l app.kubernetes.io/name=command-pod -o custom-columns=NAMESPACE:.metadata.namespace --no-headers 2>/dev/null | sort -u
}

need_pod() {
  local pod
  pod="$(pod_name)"
  [[ -n "$pod" ]] || die "no running command pod in namespace $COMMAND_POD_NS (run: command-pod.sh ensure)"
  echo "$pod"
}

cmd_shell() {
  local pod
  pod="$(need_pod)"
  exec kubectl ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} -n "$COMMAND_POD_NS" exec -it "$pod" -- bash
}

cmd_run() {
  [[ "${1:-}" == "--" ]] && shift
  [[ $# -gt 0 ]] || die "usage: command-pod.sh run -- CMD [ARGS]"
  local pod
  pod="$(need_pod)"
  kube -n "$COMMAND_POD_NS" exec -i "$pod" -- "$@"
}

# sync SRC_DIR DEST_DIR: stream a tarball through kubectl exec (works without kubectl cp quirks).
cmd_sync() {
  local src="${1:?usage: command-pod.sh sync SRC_DIR DEST_DIR}" dest="${2:?usage: command-pod.sh sync SRC_DIR DEST_DIR}"
  [[ -d "$src" ]] || die "not a directory: $src"
  local pod
  pod="$(need_pod)"
  tar -C "$src" -czf - \
    --exclude=.git --exclude=.terraform --exclude='*.tfstate*' --exclude=.venv --exclude=__pycache__ --exclude=build . \
    | kube -n "$COMMAND_POD_NS" exec -i "$pod" -- sh -c "mkdir -p '$dest' && tar -xzf - -C '$dest'"
  log "synced $src -> command pod:$dest"
}

cmd_destroy() {
  confirm "Delete the command pod from namespace $COMMAND_POD_NS?" || exit 0
  kube -n "$COMMAND_POD_NS" delete deployment command-pod --ignore-not-found
  kube -n "$COMMAND_POD_NS" delete serviceaccount command-pod --ignore-not-found
  local ns
  for ns in $(kube get rolebinding -A -l app.kubernetes.io/name=command-pod -o custom-columns=NAMESPACE:.metadata.namespace --no-headers 2>/dev/null | sort -u); do
    kube -n "$ns" delete rolebinding,role command-pod-configure --ignore-not-found
  done
  if [[ "${DELETE_NAMESPACE:-0}" == "1" ]]; then
    kube delete namespace "$COMMAND_POD_NS" --ignore-not-found
  fi
  log "command pod removed"
}

case "${1:-}" in
  deploy)  shift; cmd_deploy "$@" ;;
  ensure)  shift; cmd_ensure ;;
  grant)   shift; [[ $# -gt 0 ]] || die "usage: command-pod.sh grant NS [NS...]"; apply_rbac "$@" ;;
  scale)   shift; cmd_scale "$@" ;;
  status)  cmd_status ;;
  shell)   cmd_shell ;;
  run)     shift; cmd_run "$@" ;;
  sync)    shift; cmd_sync "$@" ;;
  destroy) cmd_destroy ;;
  -h|--help|help|"") usage ;;
  *) die "unknown command: $1 (see command-pod.sh --help)" ;;
esac
