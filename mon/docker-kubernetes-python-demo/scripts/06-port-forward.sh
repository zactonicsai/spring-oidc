#!/usr/bin/env bash
# Phase 6 — open the app in your browser (port-forward every PUBLIC service).
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT
port=8080
for svc in $PUBLIC_SERVICES; do
  name="$(svc_var "$svc" K8S_NAME)"
  log "$svc -> http://localhost:$port   (kubectl -n $APP_NAMESPACE port-forward svc/$name $port:$(svc_var "$svc" PORT))"
  kubectl -n "$APP_NAMESPACE" port-forward "svc/$name" "$port:$(svc_var "$svc" PORT)" & PIDS+=($!)
  port=$((port+1))
done
echo "Press Ctrl+C to stop."
wait
