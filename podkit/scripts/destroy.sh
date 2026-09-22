#!/usr/bin/env bash
# Destroy a generated pod build directory (build/<provider>/<name>).
#
#   destroy.sh [-m kubectl|terraform] [-y] BUILD_DIR
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

mode="kubectl" auto=""
while getopts ":m:yh" opt; do
  case $opt in
    m) mode=$OPTARG ;; y) auto=1 ;; h) sed -n '2,5p' "${BASH_SOURCE[0]}"; exit 0 ;; *) die "unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))
build_dir="${1:-}"
[[ -n "$build_dir" && -f "$build_dir/pod.env" ]] || die "usage: destroy.sh [-m kubectl|terraform] [-y] BUILD_DIR"
build_dir="$(cd "$build_dir" && pwd)"
[[ -n "$auto" ]] && export PODKIT_YES=1

case "$mode" in
  kubectl)
    exec "$build_dir/destroy.sh" ;;
  terraform)
    require_cmd terraform
    load_env_file "$build_dir/pod.env"
    confirm "Destroy $NAME ($NAMESPACE) with Terraform?" || exit 0
    (
      cd "$build_dir/terraform"
      terraform init -input=false >/dev/null
      terraform destroy -input=false ${PODKIT_YES:+-auto-approve}
    )
    log "Destroyed $NAME with Terraform" ;;
  *) die "unknown mode: $mode (kubectl|terraform)" ;;
esac
