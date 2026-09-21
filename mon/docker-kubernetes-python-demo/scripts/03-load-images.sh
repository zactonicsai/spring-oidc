#!/usr/bin/env bash
# Phase 3 — copy the images from your Docker into the kind nodes (they have their own image store).
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
CLUSTER_NAME="${CLUSTER_NAME:-$KIND_CLUSTER_NAME}"
for svc in $SERVICES; do
  image="$(svc_var "$svc" IMAGE)"
  log "kind load docker-image $image --name $CLUSTER_NAME"
  kind load docker-image "$image" --name "$CLUSTER_NAME"
done
ok "images are now inside the '$CLUSTER_NAME' nodes"
