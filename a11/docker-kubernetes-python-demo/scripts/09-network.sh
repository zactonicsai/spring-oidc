#!/usr/bin/env bash
# Phase 9 — network access: list the rules, test who can talk to whom, toggle enforcement.
#   ./scripts/09-network.sh show
#   ./scripts/09-network.sh test          # web->api allowed, stranger->api blocked
#   ./scripts/09-network.sh off | on      # helm upgrade with networkPolicy.enabled=false|true
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
API="$(svc_var api K8S_NAME)"; WEB="$(svc_var web K8S_NAME)"
mapfile -t VALUES < <(helm_values_args)
case "${1:-show}" in
  show) kubectl -n "$APP_NAMESPACE" get networkpolicy; echo; kubectl -n "$APP_NAMESPACE" describe networkpolicy "$API-allow" ;;
  test)
    log "web -> api (should be ALLOWED)"
    kubectl -n "$APP_NAMESPACE" exec "deploy/$WEB" -- python3 -c "import urllib.request;print(urllib.request.urlopen('http://$API/health',timeout=5).read().decode())"
    log "stranger pod -> api (should be BLOCKED: times out after 5s)"
    kubectl -n "$APP_NAMESPACE" run stranger --rm -i --restart=Never --image=curlimages/curl:8.12.1 --quiet -- curl -sS -m 5 "http://$API/health" \
      && warn "reached api — is the policy engine running?" || ok "blocked" ;;
  off) helm upgrade "$APP_NAME" "$ROOT/helm/python-demo" -n "$APP_NAMESPACE" "${VALUES[@]}" --set networkPolicy.enabled=false --wait; kubectl -n "$APP_NAMESPACE" get networkpolicy ;;
  on)  helm upgrade "$APP_NAME" "$ROOT/helm/python-demo" -n "$APP_NAMESPACE" "${VALUES[@]}" --set networkPolicy.enabled=true  --wait; kubectl -n "$APP_NAMESPACE" get networkpolicy ;;
  *) die "usage: $0 show | test | off | on" ;;
esac
