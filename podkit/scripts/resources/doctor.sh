#!/usr/bin/env bash
# podkit resource: environment checks.
# shellcheck shell=bash

RESOURCE_DESC="Check the local tools, cluster access and (for a build) the cloud CLI"
RESOURCE_VERBS="check"

resource_usage() {
  cat <<'USAGE'
  podkit doctor [BUILD_DIR]     verify kubectl, terraform/tofu, docker, python, ansible, openssl, keytool, cloud CLI, cluster access
USAGE
}

doctor_check_cmd() {
  local c=$1 needed=$2 ver
  if command -v "$c" >/dev/null 2>&1; then
    ver="$("$c" --version 2>/dev/null | head -n 1 || true)"
    printf '  \033[32mok\033[0m       %-16s %s\n' "$c" "${ver:0:60}"
  elif [[ "$needed" == "required" ]]; then
    printf '  \033[31mmissing\033[0m  %-16s (required)\n' "$c"; return 1
  else
    printf '  \033[33mmissing\033[0m  %-16s (optional: %s)\n' "$c" "$needed"
  fi
}

doctor_run() {
  local dir=${1:-} rc=0
  echo "tools:"
  doctor_check_cmd kubectl required || rc=1
  doctor_check_cmd python3 required || rc=1
  doctor_check_cmd terraform "Terraform path / identities" || doctor_check_cmd tofu "Terraform path / identities" || true
  doctor_check_cmd docker "building the command pod image"
  doctor_check_cmd ansible-playbook "running Ansible steps locally (CONFIGURE_VIA=local)"
  doctor_check_cmd openssl "running the keystore step locally"
  doctor_check_cmd keytool "running the keystore step locally"
  doctor_check_cmd psql "running the Postgres step locally"
  echo
  if [[ -n "$dir" ]]; then
    build_load "$dir"
    # shellcheck source=../lib/cloud.sh
    source "$PODKIT_ROOT/scripts/lib/cloud.sh"
    echo "build $BUILD_DIR ($(provider_title "$PROVIDER"), cluster $CLUSTER_NAME):"
    doctor_check_cmd "$(cloud_cli "$PROVIDER")" required || rc=1
    [[ "$PROVIDER" == "azure" ]] && doctor_check_cmd kubelogin "Entra ID clusters"
    echo
  fi
  echo "cluster:"
  if dry_run; then echo "  (dry-run)"; elif kube version >/dev/null 2>&1; then
    printf '  \033[32mok\033[0m       context %s\n' "$(current_context)"
    if [[ -n "$dir" ]]; then
      local can
      can="$(kube auth can-i create deployments -n "$NAMESPACE" 2>/dev/null || echo no)"
      printf '  %-8s create deployments in %s: %s\n' "$([[ $can == yes ]] && printf '\033[32mok\033[0m' || printf '\033[31mno\033[0m')" "$NAMESPACE" "$can"
      [[ "$can" == "yes" ]] || rc=1
    fi
  else
    printf '  \033[31mno access\033[0m  kubectl cannot reach a cluster (podkit cluster login ...)\n'; rc=1
  fi
  return $rc
}

cmd_check()    { doctor_run "$@"; }
cmd__default() { doctor_run "$@"; }
