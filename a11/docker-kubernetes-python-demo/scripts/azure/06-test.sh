#!/usr/bin/env bash
# Azure phase 6 — test through the public IP + run the chart's own tests.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env registry
WEB="$(svc_var web K8S_NAME)"; API="$(svc_var api K8S_NAME)"
ip="$(public_ip_of_service "$WEB")"; [[ -n "$ip" ]] || die "no public IP yet for $WEB"
base="http://$ip:$(svc_var web PORT)"
log "1) web health via the Azure load balancer";   curl -fsS "$base/health"; echo
log "2) web page (which pod answered?)";           curl -fsS "$base/?name=Azure" | grep -E "h1|Pod|API says"
log "3) web -> api inside the cluster";            curl -fsS "$base/api-config"; echo
log "4) api is NOT public (expect connection failure / timeout)"
if kubectl -n "$APP_NAMESPACE" get svc "$API" -o jsonpath='{.spec.type}' | grep -q LoadBalancer; then warn "api is exposed publicly!"; else ok "api has no public IP (ClusterIP only)"; fi
log "5) network policy: stranger pod -> api must be blocked"
kubectl -n "$APP_NAMESPACE" run np-test --rm -i --restart=Never --image=curlimages/curl:8.12.1 --quiet -- curl -sS -m 5 "http://$API/health" \
  && die "policy NOT enforced" || ok "blocked by Cilium network policy"
log "6) helm test"
helm test "$APP_NAME" -n "$APP_NAMESPACE" --logs
ok "all Azure tests passed — open $base in a browser"
