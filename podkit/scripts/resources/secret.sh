#!/usr/bin/env bash
# podkit resource: Kubernetes Secrets, including the deploy-time sync from the cloud secret store.
# shellcheck shell=bash

RESOURCE_DESC="Secrets: sync from the cloud store into <name>-env, get/set/list, destroy"
RESOURCE_VERBS="sync get set list destroy"

resource_usage() {
  cat <<'USAGE'
  podkit secret sync BUILD_DIR                         cloud store (Secrets Manager / Key Vault / Secret Manager) -> Secret <name>-env
  podkit secret get NS NAME [KEY]                      list keys, or print one decoded value
  podkit secret set NS NAME KEY=VALUE... [--file KEY=PATH]...   create or update an Opaque Secret (server-side apply)
  podkit secret list [NS]                              Secrets podkit manages
  podkit secret destroy BUILD_DIR | NS NAME            delete the build's env Secret, or any Secret
USAGE
}

# shellcheck source=../lib/cloud.sh
source "$PODKIT_ROOT/scripts/lib/cloud.sh"

secret_exists() { kube -n "$1" get secret "$2" >/dev/null 2>&1; }

# secret_apply NS NAME [--from-literal=K=V | --from-file=K=PATH]... -> create-or-update with podkit labels
secret_apply() {
  local ns=$1 name=$2; shift 2
  kube -n "$ns" create secret generic "$name" "$@" --dry-run=client -o yaml \
    | kube apply --server-side --field-manager=podkit --force-conflicts -f - >/dev/null
  kube -n "$ns" label secret "$name" --overwrite "$(managed_label)" >/dev/null
}

# secret_checksum NS NAME -> short hash of the data (used to roll pods when values change)
secret_checksum() {
  dry_run && { echo "dry-run"; return 0; }
  kube -n "$1" get secret "$2" -o jsonpath='{.data}' | sha256sum | cut -c1-16
}

# secret_sync_build BUILD_DIR -> read every CLOUD_SECRETS entry (ENV=ref) and write Secret $ENV_SECRET; prints the checksum
secret_sync_build() {
  build_load "$1"
  if [[ -z "${CLOUD_SECRETS:-}" ]]; then echo "none"; return 0; fi
  require_cmd kubectl "$(cloud_cli "$PROVIDER")"
  local pair env ref args=() count=0
  while IFS= read -r pair; do
    env=${pair%%=*}; ref=${pair#*=}
    args+=("--from-literal=$env=$(cloud_secret_get "$PROVIDER" "$ref")")
    count=$((count + 1))
  done < <(split_csv "$CLOUD_SECRETS")
  log "syncing $count secret(s) from $(secret_store_name "$PROVIDER") into Secret $NAMESPACE/$ENV_SECRET"
  secret_apply "$NAMESPACE" "$ENV_SECRET" "${args[@]}"
  secret_checksum "$NAMESPACE" "$ENV_SECRET"
}

secret_get() {
  local ns=$1 name=$2 key=${3:-}
  if [[ -n "$key" ]]; then
    kube -n "$ns" get secret "$name" -o go-template="{{index .data \"$key\"}}" | base64 -d; echo
  else
    # shellcheck disable=SC2016  # go-template, not shell
    kube -n "$ns" get secret "$name" -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}'
  fi
}

secret_destroy() {
  local ns=$1 name=$2
  confirm "Delete Secret $ns/$name?" || return 0
  kube -n "$ns" delete secret "$name" --ignore-not-found
}

cmd_sync() { secret_sync_build "${1:-}" >/dev/null; log "done"; }
cmd_get()  { [[ $# -ge 2 ]] || die "usage: podkit secret get NS NAME [KEY]"; secret_get "$@"; }
cmd_set() {
  [[ $# -ge 3 ]] || die "usage: podkit secret set NS NAME KEY=VALUE... [--file KEY=PATH]..."
  local ns=$1 name=$2; shift 2
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) args+=("--from-file=$2"); shift 2 ;;
      *=*)    args+=("--from-literal=$1"); shift ;;
      *) die "expected KEY=VALUE, got: $1" ;;
    esac
  done
  secret_apply "$ns" "$name" "${args[@]}"
  log "Secret $ns/$name updated (${#args[@]} key(s))"
}
cmd_list() { if [[ -n "${1:-}" ]]; then kube -n "$1" get secrets -l "$(managed_label)"; else kube get secrets -A -l "$(managed_label)"; fi; }
cmd_destroy() {
  if [[ $# -eq 1 ]]; then
    build_load "$1"
    [[ -n "${ENV_SECRET:-}" ]] || die "build has no env Secret"
    secret_destroy "$NAMESPACE" "$ENV_SECRET"
  elif [[ $# -eq 2 ]]; then
    secret_destroy "$1" "$2"
  else
    die "usage: podkit secret destroy BUILD_DIR | NS NAME"
  fi
}
