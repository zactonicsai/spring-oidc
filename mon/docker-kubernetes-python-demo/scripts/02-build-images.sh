#!/usr/bin/env bash
# Phase 2 — build one Docker image per service listed in app.config.yaml.
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
for svc in $SERVICES; do
  image="$(svc_var "$svc" IMAGE)"; ctx="$(svc_var "$svc" BUILD_CONTEXT)"; df="$(svc_var "$svc" DOCKERFILE)"
  log "docker build $image  (context: $ctx)"
  docker build --pull -t "$image" -f "$ROOT/$ctx/$df" "$ROOT/$ctx"
  ok "built $image"
done
docker images --filter "reference=${APP_NAME}-*" --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'
