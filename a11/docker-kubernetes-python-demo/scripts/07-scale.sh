#!/usr/bin/env bash
# Phase 7 — scaling: manual (kubectl scale), automatic (HPA), and a load generator to watch it happen.
#   ./scripts/07-scale.sh manual web 4      # set replicas by hand (HPA will fight you if enabled!)
#   ./scripts/07-scale.sh load 60           # hammer api /api/work for 60s, watch the HPA add pods
#   ./scripts/07-scale.sh watch             # live view of pods + hpa
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
mode="${1:-watch}"
case "$mode" in
  manual)
    svc="${2:?service name}"; n="${3:?replica count}"
    name="$(svc_var "$svc" K8S_NAME)"
    warn "if an HPA exists for $name it will scale back to its min/max range within ~1 minute"
    kubectl -n "$APP_NAMESPACE" scale "deployment/$name" --replicas="$n"
    kubectl -n "$APP_NAMESPACE" rollout status "deployment/$name" ;;
  load)
    secs="${2:-60}"; name="$(svc_var api K8S_NAME)"
    log "Generating CPU load on $name for ${secs}s (the api's /api/work endpoint burns CPU)"
    kubectl -n "$APP_NAMESPACE" run load-gen --rm -i --restart=Never --image=curlimages/curl:8.12.1 --quiet \
      --labels="app.kubernetes.io/name=$APP_NAME,app.kubernetes.io/component=web" \
      -- sh -c "end=\$((\$(date +%s)+$secs)); while [ \$(date +%s) -lt \$end ]; do curl -s -m 5 'http://$name/api/work?ms=300' >/dev/null & sleep 0.1; done; wait" &
    # (the load pod borrows web's labels so the network policy lets it reach api)
    kubectl -n "$APP_NAMESPACE" get hpa -w & PIDS=$!
    sleep "$((secs+90))"; kill "$PIDS" 2>/dev/null || true ;;
  watch)
    watch -n 2 "kubectl -n $APP_NAMESPACE get hpa; echo; kubectl -n $APP_NAMESPACE get pods -o wide; echo; kubectl -n $APP_NAMESPACE top pods 2>/dev/null" ;;
  *) die "usage: $0 manual <svc> <n> | load [seconds] | watch" ;;
esac
