#!/usr/bin/env bash
# podkit resource: pod-to-pod mTLS material (CA, per-pod Java keystore, shared truststore) stored as Secrets.
# The issuing logic lives in ansible/playbooks/java-keystore.yml and configure/java-keystore.sh.
# shellcheck shell=bash

RESOURCE_DESC="mTLS material: issue/rotate a pod's keystore + shared CA/truststore Secrets, status, destroy"
RESOURCE_VERBS="issue rotate status destroy"

resource_usage() {
  cat <<'USAGE'
  podkit tls issue BUILD_DIR [--via local]      run the build's keystore step (idempotent; needs spec.tls)
  podkit tls rotate BUILD_DIR [--via local]     reissue the pod's certificate and roll its pods
  podkit tls status NS [NAME]                   CA / truststore / keystore Secrets with certificate expiry
  podkit tls destroy BUILD_DIR | NS NAME [--ca] delete a keystore Secret; --ca also deletes the shared CA and truststore
  Rotate the CA: podkit tls destroy BUILD_DIR --ca, then podkit tls rotate for every pod in the namespace.
USAGE
}

tls_require_build() {
  build_load "$1"
  [[ "${TLS_ENABLED:-false}" == "true" ]] || die "$NAME has no spec.tls block"
  case "${CONFIGURE_TARGET:-}" in
    *java-keystore*) ;;
    *) die "$NAME's configuration step is not the keystore flow (spec.configure overrides it); run it manually" ;;
  esac
}

# tls_issue_build BUILD_DIR [rotate] [--via X]
tls_issue_build() {
  local dir=$1 rotate=${2:-0}; shift 2
  tls_require_build "$dir"
  plugin_source configure
  local extra=()
  if [[ "$rotate" == "1" ]]; then
    if [[ "$CONFIGURE_METHOD" == "ansible" ]]; then extra=(-e rotate=true); else extra=(ROTATE=true); fi
  fi
  log "$([[ $rotate == 1 ]] && echo rotating || echo issuing) keystore for $NAME ($CONFIGURE_METHOD)"
  configure_run_build "$dir" "$@" ${extra[@]+"${extra[@]}"}
}

# tls_cert_summary NS SECRET -> "subject, expiry" from tls.crt (needs openssl)
tls_cert_summary() {
  local crt
  crt="$(kube -n "$1" get secret "$2" -o go-template='{{index .data "tls.crt"}}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  [[ -n "$crt" ]] || { echo "(no tls.crt)"; return 0; }
  if command -v openssl >/dev/null 2>&1; then
    openssl x509 -noout -subject -enddate <<<"$crt" | tr '\n' ' '
  else
    echo "(openssl not installed)"
  fi
}

# tls_status NS [NAME]
tls_status() {
  local ns=$1 name=${2:-}
  echo "namespace: $ns"
  dry_run && { kube -n "$ns" get secrets -l podkit.dev/component=mtls; return 0; }
  local s role
  while read -r s role; do
    [[ -n "$s" ]] || continue
    [[ -n "$name" && "$role" == "keystore" && "$s" != "$name-keystore" ]] && continue
    case "$role" in
      keystore) printf '  %-11s %-32s %s\n' "$role" "$s" "$(tls_cert_summary "$ns" "$s")" ;;
      ca)       printf '  %-11s %-32s %s\n' "$role" "$s" "$(kube -n "$ns" get secret "$s" -o go-template='{{index .data "ca.crt"}}' | base64 -d | openssl x509 -noout -subject -enddate 2>/dev/null | tr '\n' ' ')" ;;
      *)        printf '  %-11s %s\n' "$role" "$s" ;;
    esac
  done < <(kube -n "$ns" get secrets -l podkit.dev/component=mtls -o go-template='{{range .items}}{{.metadata.name}} {{index .metadata.labels "podkit.dev/role"}}{{"\n"}}{{end}}' 2>/dev/null)
}

# tls_destroy NS KEYSTORE_SECRET [with_ca] [CA_SECRET] [TRUSTSTORE_SECRET]
tls_destroy() {
  local ns=$1 keystore=$2 with_ca=${3:-0} ca=${4:-podkit-mtls-ca} truststore=${5:-podkit-mtls-truststore}
  local what="keystore Secret $ns/$keystore"
  [[ "$with_ca" == "1" ]] && what+=" plus the shared CA ($ca) and truststore ($truststore): every pod in $ns must be rotated afterwards"
  confirm "Delete $what?" || return 0
  kube -n "$ns" delete secret "$keystore" --ignore-not-found
  if [[ "$with_ca" == "1" ]]; then
    kube -n "$ns" delete secret "$ca" "$truststore" --ignore-not-found
  fi
  log "deleted"
}

cmd_issue()  { [[ -n "${1:-}" ]] || die "usage: podkit tls issue BUILD_DIR [--via X]"; local d=$1; shift; tls_issue_build "$d" 0 "$@"; }
cmd_rotate() { [[ -n "${1:-}" ]] || die "usage: podkit tls rotate BUILD_DIR [--via X]"; local d=$1; shift; tls_issue_build "$d" 1 "$@"; }
cmd_status() { [[ -n "${1:-}" ]] || die "usage: podkit tls status NS [NAME]"; tls_status "$@"; }
cmd_destroy() {
  local with_ca=0 pos=() a
  for a in "$@"; do case "$a" in --ca) with_ca=1 ;; *) pos+=("$a") ;; esac; done
  if [[ ${#pos[@]} -eq 1 ]]; then
    tls_require_build "${pos[0]}"
    tls_destroy "$NAMESPACE" "$TLS_KEYSTORE_SECRET" "$with_ca" "$TLS_CA_SECRET" "$TLS_TRUSTSTORE_SECRET"
  elif [[ ${#pos[@]} -eq 2 ]]; then
    tls_destroy "${pos[0]}" "${pos[1]}" "$with_ca"
  else
    die "usage: podkit tls destroy BUILD_DIR | NS NAME [--ca]"
  fi
}
