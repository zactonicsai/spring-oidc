#!/usr/bin/env bash
# Shell twin of ansible/playbooks/run-script.yml: copy a script into every running pod of a
# workload and execute it there.
#
# Inputs (env): NAMESPACE TARGET_SELECTOR CONTAINER SCRIPT (path; relative to BUILD_DIR unless absolute) SCRIPT_ARGS
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
apply_overrides "$@"
require_cmd kubectl

: "${NAMESPACE:?}" "${TARGET_SELECTOR:?}" "${CONTAINER:?}" "${SCRIPT:?SCRIPT is required}"
SCRIPT_ARGS="${SCRIPT_ARGS:-}"
[[ "$SCRIPT" == /* ]] || SCRIPT="${BUILD_DIR:?BUILD_DIR is required for a relative SCRIPT}/$SCRIPT"
[[ -f "$SCRIPT" ]] || die "script not found: $SCRIPT"
remote="/tmp/podkit-$(basename "$SCRIPT")"

mapfile -t pods < <(running_pods "$NAMESPACE" "$TARGET_SELECTOR")
[[ ${#pods[@]} -gt 0 ]] || die "no running pod matches $TARGET_SELECTOR in $NAMESPACE"
for pod in "${pods[@]}"; do
  kube cp "$SCRIPT" "$NAMESPACE/$pod:$remote" -c "$CONTAINER"
  log "$pod: running $remote $SCRIPT_ARGS"
  # shellcheck disable=SC2086
  kube -n "$NAMESPACE" exec "$pod" -c "$CONTAINER" -- sh "$remote" $SCRIPT_ARGS
done
