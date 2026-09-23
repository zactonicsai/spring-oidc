#!/usr/bin/env bash
# podkit resource: the in-cluster command pod where configuration steps run (kubectl, Ansible,
# openssl, keytool, psql). Small, namespaced RBAC only, scale to zero when idle.
# shellcheck shell=bash

RESOURCE_DESC="Command pod: deploy/ensure, grant namespaces, scale, shell, run, sync, destroy"
RESOURCE_VERBS="deploy ensure grant revoke scale status shell run sync destroy"

resource_usage() {
  cat <<'USAGE'
  podkit command-pod deploy [REPLICAS]      create/update namespace, ServiceAccount, RBAC and Deployment, wait until ready
  podkit command-pod ensure                 deploy if missing, scale up if idle, wait until ready (idempotent)
  podkit command-pod grant NS [NS...]       allow it to configure more namespaces (namespaced Role + RoleBinding)
  podkit command-pod revoke NS [NS...]      remove those permissions
  podkit command-pod scale N                0 = idle (costs nothing)
  podkit command-pod status                 pod, image and granted namespaces
  podkit command-pod shell                  interactive shell inside the pod
  podkit command-pod run -- CMD [ARGS]      run a command inside the pod
  podkit command-pod sync SRC_DIR DEST      copy a local directory into the pod (tar over kubectl exec)
  podkit command-pod destroy                delete Deployment, RBAC and ServiceAccount (DELETE_NAMESPACE=1: namespace too)
  Environment: COMMAND_POD_NS (ops), COMMAND_POD_IMAGE, TARGET_NAMESPACES (csv), COMMAND_POD_WAIT (180s)
USAGE
}

COMMAND_POD_NS="${COMMAND_POD_NS:-ops}"
COMMAND_POD_IMAGE="${COMMAND_POD_IMAGE:-ghcr.io/your-org/podkit-command-pod:latest}"
COMMAND_POD_SELECTOR="app.kubernetes.io/name=command-pod"
COMMAND_POD_MANIFESTS="$PODKIT_ROOT/command-pod/k8s"

commandpod_pod_name() {
  kube -n "$COMMAND_POD_NS" get pod -l "$COMMAND_POD_SELECTOR" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

commandpod_exists() { kube -n "$COMMAND_POD_NS" get deployment command-pod >/dev/null 2>&1; }

# commandpod_grant NS... -> namespaced Role + RoleBinding in each namespace (created if missing)
commandpod_grant() {
  local ns
  for ns in "$@"; do
    [[ -n "$ns" ]] || continue
    kube get namespace "$ns" >/dev/null 2>&1 || kube create namespace "$ns" >/dev/null
    render_template "$COMMAND_POD_MANIFESTS/rbac.yaml" "TARGET_NAMESPACE=$ns" "COMMAND_POD_NS=$COMMAND_POD_NS" \
      | kube apply --server-side --field-manager=podkit -f - >/dev/null
    log "command pod may configure namespace '$ns'"
  done
}

commandpod_revoke() {
  local ns
  for ns in "$@"; do
    kube -n "$ns" delete rolebinding,role command-pod-configure --ignore-not-found
    log "command pod access to namespace '$ns' removed"
  done
}

commandpod_wait_ready() {
  log "waiting for the command pod to be ready"
  kube -n "$COMMAND_POD_NS" rollout status deployment/command-pod --timeout="${COMMAND_POD_WAIT:-180s}"
}

# commandpod_deploy [REPLICAS]
commandpod_deploy() {
  require_cmd kubectl
  local replicas="${1:-1}" namespaces=()
  log "deploying command pod to namespace $COMMAND_POD_NS (image: $COMMAND_POD_IMAGE)"
  render_template "$COMMAND_POD_MANIFESTS/command-pod.yaml" "COMMAND_POD_NS=$COMMAND_POD_NS" \
    "COMMAND_POD_IMAGE=$COMMAND_POD_IMAGE" "REPLICAS=$replicas" \
    | kube apply --server-side --field-manager=podkit -f -
  mapfile -t namespaces < <(split_csv "${TARGET_NAMESPACES:-default}")
  commandpod_grant "${namespaces[@]}"
  [[ "$replicas" -gt 0 ]] && commandpod_wait_ready
  return 0
}

commandpod_ensure() {
  require_cmd kubectl
  if ! dry_run && ! commandpod_exists; then
    commandpod_deploy 1
    return
  fi
  local namespaces=() replicas
  mapfile -t namespaces < <(split_csv "${TARGET_NAMESPACES:-default}")
  commandpod_grant "${namespaces[@]}"
  replicas="$(kube -n "$COMMAND_POD_NS" get deployment command-pod -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)"
  if [[ "${replicas:-0}" -lt 1 ]]; then
    log "command pod is idle; scaling to 1"
    kube -n "$COMMAND_POD_NS" scale deployment/command-pod --replicas=1 >/dev/null
  fi
  commandpod_wait_ready
}

commandpod_scale() {
  kube -n "$COMMAND_POD_NS" scale deployment/command-pod --replicas="$1"
  log "command pod scaled to $1 replica(s)"
}

commandpod_status() {
  if ! dry_run && ! commandpod_exists; then log "command pod is not deployed in namespace $COMMAND_POD_NS"; return 0; fi
  kube -n "$COMMAND_POD_NS" get deployment command-pod -o wide
  kube -n "$COMMAND_POD_NS" get pod -l "$COMMAND_POD_SELECTOR" -o wide
  log "granted namespaces:"
  kube get rolebinding -A -l app.kubernetes.io/name=command-pod -o custom-columns=NAMESPACE:.metadata.namespace --no-headers 2>/dev/null | sort -u
}

commandpod_need_pod() {
  local pod
  pod="$(commandpod_pod_name)"
  dry_run && pod="${pod:-command-pod-dry-run}"
  [[ -n "$pod" ]] || die "no running command pod in namespace $COMMAND_POD_NS (run: podkit command-pod ensure)"
  echo "$pod"
}

commandpod_run() {
  [[ "${1:-}" == "--" ]] && shift
  [[ $# -gt 0 ]] || die "usage: podkit command-pod run -- CMD [ARGS]"
  local pod
  pod="$(commandpod_need_pod)"
  kube -n "$COMMAND_POD_NS" exec -i "$pod" -- "$@"
}

# commandpod_sync SRC_DIR DEST_DIR -> stream a tarball through kubectl exec
commandpod_sync() {
  local src=$1 dest=$2 pod
  [[ -d "$src" ]] || die "not a directory: $src"
  pod="$(commandpod_need_pod)"
  if dry_run; then log "[dry-run] sync $src -> command pod:$dest"; return 0; fi
  tar -C "$src" -czf - \
    --exclude=.git --exclude=.terraform --exclude='*.tfstate*' --exclude=.venv --exclude=__pycache__ --exclude=build . \
    | kube -n "$COMMAND_POD_NS" exec -i "$pod" -- sh -c "mkdir -p '$dest' && tar -xzf - -C '$dest'"
  log "synced $src -> command pod:$dest"
}

commandpod_destroy() {
  confirm "Delete the command pod from namespace $COMMAND_POD_NS?" || return 0
  kube -n "$COMMAND_POD_NS" delete deployment command-pod --ignore-not-found
  kube -n "$COMMAND_POD_NS" delete serviceaccount command-pod --ignore-not-found
  local ns
  for ns in $(kube get rolebinding -A -l app.kubernetes.io/name=command-pod -o custom-columns=NAMESPACE:.metadata.namespace --no-headers 2>/dev/null | sort -u); do
    commandpod_revoke "$ns"
  done
  if [[ "${DELETE_NAMESPACE:-0}" == "1" ]]; then
    kube delete namespace "$COMMAND_POD_NS" --ignore-not-found
  fi
  log "command pod removed"
}

cmd_deploy()  { commandpod_deploy "$@"; }
cmd_ensure()  { commandpod_ensure; }
cmd_grant()   { [[ $# -gt 0 ]] || die "usage: podkit command-pod grant NS [NS...]"; commandpod_grant "$@"; }
cmd_revoke()  { [[ $# -gt 0 ]] || die "usage: podkit command-pod revoke NS [NS...]"; commandpod_revoke "$@"; }
cmd_scale()   { commandpod_scale "${1:?usage: podkit command-pod scale N}"; }
cmd_status()  { commandpod_status; }
cmd_shell()   { local pod; pod="$(commandpod_need_pod)"; dry_run && return 0; exec kubectl ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} -n "$COMMAND_POD_NS" exec -it "$pod" -- bash; }
cmd_run()     { commandpod_run "$@"; }
cmd_sync()    { [[ $# -eq 2 ]] || die "usage: podkit command-pod sync SRC_DIR DEST_DIR"; commandpod_sync "$1" "$2"; }
cmd_destroy() { commandpod_destroy; }
