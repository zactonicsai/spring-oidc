#!/usr/bin/env bash
# Deploy a generated pod build directory (build/<provider>/<name>).
#
#   deploy.sh [-m kubectl|terraform] [-y] BUILD_DIR
#
#   kubectl   (default) runs BUILD_DIR/deploy.sh: secrets, ServiceAccount, manifests, rollout, configuration.
#   terraform runs terraform init/apply in BUILD_DIR/terraform (also creates the cloud identity and reads
#             secrets from the cloud store), then the configuration step.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

mode="kubectl" auto=""
while getopts ":m:yh" opt; do
  case $opt in
    m) mode=$OPTARG ;; y) auto=1 ;; h) sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;; *) die "unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))
build_dir="${1:-}"
[[ -n "$build_dir" && -f "$build_dir/pod.env" ]] || die "usage: deploy.sh [-m kubectl|terraform] [-y] BUILD_DIR (generate it with: python -m podgen generate ...)"
build_dir="$(cd "$build_dir" && pwd)"
[[ -n "$auto" ]] && export PODKIT_YES=1

case "$mode" in
  kubectl)
    exec "$build_dir/deploy.sh" ;;
  terraform)
    require_cmd terraform kubectl
    load_env_file "$build_dir/pod.env"
    if [[ "$CONFIGURE_METHOD" != "none" && "$CONFIGURE_PHASE" == "pre" ]]; then
      BUILD_DIR="$build_dir" "$build_dir/configure.sh"
    fi
    (
      cd "$build_dir/terraform"
      terraform init -input=false
      terraform apply -input=false ${PODKIT_YES:+-auto-approve}
      identity="$(terraform output -raw identity 2>/dev/null || true)"
      if [[ -n "$identity" && "$identity" != "null" ]]; then
        log "Cloud identity: $identity (export IDENTITY_ID=$identity for the kubectl path)"
      fi
    )
    if [[ "$CONFIGURE_METHOD" != "none" && "$CONFIGURE_PHASE" == "post" ]]; then
      BUILD_DIR="$build_dir" "$build_dir/configure.sh"
    fi
    log "Deployed $NAME with Terraform" ;;
  *) die "unknown mode: $mode (kubectl|terraform)" ;;
esac
