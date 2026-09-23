#!/usr/bin/env bash
# podkit resource: the pod's cloud identity (IAM role / managed identity / Google service account),
# created by the build's Terraform module.cloud and bound to the ServiceAccount by annotation.
# shellcheck shell=bash

RESOURCE_DESC="Cloud identity for a pod (IRSA / Pod Identity, Azure Workload Identity, GKE WI) via Terraform"
RESOURCE_VERBS="apply bind status destroy"

resource_usage() {
  cat <<'USAGE'
  podkit identity apply BUILD_DIR      terraform apply -target=module.cloud, then store IDENTITY_ID in pod.env
  podkit identity bind BUILD_DIR       annotate the ServiceAccount with IDENTITY_ID (pod deploy does this too)
  podkit identity status BUILD_DIR     Terraform output and the live ServiceAccount annotation
  podkit identity destroy BUILD_DIR    terraform destroy -target=module.cloud and clear IDENTITY_ID
  Terraform reads the cloud CLI credentials; use `podkit pod deploy -m terraform` to manage identity and workload together.
USAGE
}

identity_tf_dir() { echo "$BUILD_DIR/terraform"; }

# identity_apply_build BUILD_DIR -> create the identity only (targeted apply) and record it in pod.env
identity_apply_build() {
  build_load "$1"
  [[ "${IDENTITY_ENABLED:-false}" == "true" ]] || die "identity is not enabled for $NAME (spec.identity.enabled)"
  local dir; dir="$(identity_tf_dir)"
  log "creating the cloud identity for $NAME with Terraform (module.cloud only)"
  tf "$dir" init -input=false >/dev/null
  tf "$dir" apply -input=false -target=module.cloud ${PODKIT_YES:+-auto-approve}
  if dry_run; then log "[dry-run] would store the identity output as IDENTITY_ID in $BUILD_DIR/pod.env"; return 0; fi
  local id
  id="$(tf "$dir" output -raw identity 2>/dev/null || true)"
  [[ -n "$id" && "$id" != "null" ]] || die "terraform did not return an identity output"
  set_env_value "$BUILD_DIR/pod.env" IDENTITY_ID "$id"
  log "IDENTITY_ID=$id stored in $BUILD_DIR/pod.env"
}

# identity_bind_build BUILD_DIR -> annotate the ServiceAccount (warn when IDENTITY_ID is empty)
identity_bind_build() {
  build_load "$1"
  [[ "${IDENTITY_ENABLED:-false}" == "true" ]] || return 0
  if [[ -n "${IDENTITY_ID:-}" ]]; then
    kube -n "$NAMESPACE" annotate serviceaccount "$NAME" --overwrite "$IDENTITY_ANNOTATION=$IDENTITY_ID" >/dev/null
    log "ServiceAccount $NAMESPACE/$NAME bound to $IDENTITY_ID"
  else
    warn "IDENTITY_ID is empty: $NAME is not bound to a cloud identity (run: podkit identity apply $BUILD_DIR)"
  fi
}

identity_status_build() {
  build_load "$1"
  echo "enabled   : ${IDENTITY_ENABLED:-false}"
  echo "pod.env   : ${IDENTITY_ID:-<empty>}"
  local dir; dir="$(identity_tf_dir)"
  if [[ -d "$dir/.terraform" ]] && ! dry_run; then
    echo "terraform : $(tf "$dir" output -raw identity 2>/dev/null || echo '<no output>')"
  fi
  echo "live SA   : $(kube -n "$NAMESPACE" get serviceaccount "$NAME" -o jsonpath="{.metadata.annotations.${IDENTITY_ANNOTATION//./\\.}}" 2>/dev/null || echo '<not deployed>')"
}

identity_destroy_build() {
  build_load "$1"
  local dir; dir="$(identity_tf_dir)"
  confirm "Destroy the cloud identity of $NAME (Terraform module.cloud)?" || return 0
  tf "$dir" init -input=false >/dev/null
  tf "$dir" destroy -input=false -target=module.cloud ${PODKIT_YES:+-auto-approve}
  # shellcheck disable=SC2016  # literal placeholder, expanded when pod.env is sourced
  dry_run || set_env_value "$BUILD_DIR/pod.env" IDENTITY_ID '${IDENTITY_ID:-}'
  kube -n "$NAMESPACE" annotate serviceaccount "$NAME" "${IDENTITY_ANNOTATION}-" >/dev/null 2>&1 || true
  log "identity of $NAME destroyed"
}

cmd_apply()   { identity_apply_build "${1:-}"; }
cmd_bind()    { identity_bind_build "${1:-}"; }
cmd_status()  { identity_status_build "${1:-}"; }
cmd_destroy() { identity_destroy_build "${1:-}"; }
