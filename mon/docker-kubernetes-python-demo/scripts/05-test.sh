#!/usr/bin/env bash
# Phase 5 — prove it works: health, config, secrets, web->api networking, network policy.
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
WEB="$(svc_var web K8S_NAME)"; API="$(svc_var api K8S_NAME)"
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

log "Waiting for pods"
for svc in $SERVICES; do wait_for_rollout "$APP_NAMESPACE" "$(svc_var "$svc" K8S_NAME)"; done

log "Port-forwarding web -> 18080 and api -> 18081"
kubectl -n "$APP_NAMESPACE" port-forward "svc/$WEB" "18080:$(svc_var web PORT)" >"$BUILD_DIR/pf-web.log" 2>&1 & PIDS+=($!)
kubectl -n "$APP_NAMESPACE" port-forward "svc/$API" "18081:$(svc_var api PORT)" >"$BUILD_DIR/pf-api.log" 2>&1 & PIDS+=($!)
for _ in $(seq 1 20); do curl -fsS -m 1 http://127.0.0.1:18080/health >/dev/null 2>&1 && break; sleep 0.5; done

log "1) health endpoints";        curl -fsS http://127.0.0.1:18080/health; echo; curl -fsS http://127.0.0.1:18081/health; echo
log "2) api GET + POST";          curl -fsS 'http://127.0.0.1:18081/api/hello?name=Kubernetes'; echo
                                  curl -fsS -X POST http://127.0.0.1:18081/api/hello -H 'Content-Type: application/json' -d '{"name":"Docker"}'; echo
log "3) config from ConfigMap + secret from Secret (masked)"; curl -fsS http://127.0.0.1:18081/api/config; echo
log "4) web -> api over the cluster network (Service DNS: $API)"; curl -fsS http://127.0.0.1:18080/api-config; echo
log "5) load balancing: which pod answers?"; for _ in 1 2 3 4; do curl -fsS http://127.0.0.1:18080/config | python3 -c 'import sys,json;print(" pod:",json.load(sys.stdin)["pod"])'; done

if [[ "$NETWORK_POLICY_ENABLED" == "true" ]]; then
  log "6) network policy: a random pod must NOT reach api (expect a timeout)"
  if kubectl -n "$APP_NAMESPACE" run np-test --rm -i --restart=Never --image=curlimages/curl:8.12.1 --quiet -- \
       curl -sS -m 5 "http://$API/health" >/dev/null 2>&1; then
    die "network policy is NOT enforced: an unrelated pod reached the api"
  else
    ok "blocked, as designed (only 'web' may talk to 'api')"
  fi
fi
ok "All tests passed."
