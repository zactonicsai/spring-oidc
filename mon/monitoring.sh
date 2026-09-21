#!/usr/bin/env bash
# =============================================================================
# monitoring.sh — Prometheus + Grafana (kube-prometheus-stack) with dashboards and alerts for
#                 Keycloak, the python-demo services and the devbox, exposed outside the cluster.
#
#   ./scripts/monitoring.sh deploy          # helm install kube-prometheus-stack + ServiceMonitors, rules, dashboard, scrape policies
#   ./scripts/monitoring.sh status          # pods, targets summary, URLs
#   ./scripts/monitoring.sh open            # kind: port-forward Grafana :3000, Prometheus :9090, Alertmanager :9093
#   ./scripts/monitoring.sh password        # Grafana admin password
#   ./scripts/monitoring.sh targets         # which scrape targets are up/down (needs `open` or LB)
#   ./scripts/monitoring.sh destroy
#
# Exposure: cloud context -> Grafana Service type LoadBalancer (port 80)   kind -> port-forward
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/common.sh"
NS=monitoring; MAN="$ROOT/k8s/monitoring"; CHART_VERSION="${KPS_VERSION:-}"   # e.g. KPS_VERSION=80.0.0 to pin
require kubectl helm
ctx="$(kubectl config current-context)"
is_kind=false; [[ "$ctx" == kind-* ]] && is_kind=true
if [[ -n "${USE_LB:-}" ]]; then use_lb="$USE_LB"; elif $is_kind; then use_lb=false; else use_lb=true; fi
randpw() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20; }
grafana_ip() { kubectl -n $NS get svc kps-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null; }

case "${1:-status}" in
  deploy)
    log "context $ctx · Grafana via $([[ $use_lb == true ]] && echo LoadBalancer || echo port-forward)"
    kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -
    if ! kubectl -n $NS get secret grafana-admin >/dev/null 2>&1; then
      kubectl -n $NS create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password="$(randpw)"
      ok "grafana admin secret created ($0 password)"
    fi
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update prometheus-community >/dev/null
    values=(-f "$MAN/values.yaml"); $is_kind && values+=(-f "$MAN/values-kind.yaml")
    ver=(); [[ -n "$CHART_VERSION" ]] && ver=(--version "$CHART_VERSION")
    log "helm upgrade --install kube-prometheus-stack (operator, prometheus, alertmanager, grafana, node-exporter, kube-state-metrics)"
    helm upgrade --install kps prometheus-community/kube-prometheus-stack -n $NS "${values[@]}" "${ver[@]}" --wait --timeout 10m
    log "our monitors, alert rules, dashboard and scrape network policies"
    kubectl apply -f "$MAN/servicemonitors.yaml" -f "$MAN/rules.yaml" -f "$MAN/dashboard-configmap.yaml"
    kubectl get namespace python-demo >/dev/null 2>&1 && kubectl apply -f "$MAN/netpol-allow-scrape.yaml" || warn "python-demo namespace not found yet: re-run 'deploy' after ./scripts/04-deploy-helm.sh to allow scraping"
    if [[ $use_lb == true ]]; then kubectl -n $NS patch svc kps-grafana -p '{"spec":{"type":"LoadBalancer"}}'; fi
    "$0" status ;;
  status)
    kubectl -n $NS get pods
    kubectl -n $NS get servicemonitors,prometheusrules 2>/dev/null | grep -E "keycloak|python-demo|app-and" || true
    if [[ $use_lb == true ]]; then ip="$(grafana_ip)"; [[ -n "$ip" ]] && ok "Grafana: http://$ip/  (admin / $0 password)" || warn "Grafana LoadBalancer IP pending"
    else ok "run  $0 open   then Grafana http://localhost:3000 (admin / $0 password), Prometheus http://localhost:9090, Alertmanager http://localhost:9093"; fi ;;
  open)
    ok "Grafana http://localhost:3000 · Prometheus http://localhost:9090 · Alertmanager http://localhost:9093   (Ctrl+C stops all)"
    kubectl -n $NS port-forward svc/kps-grafana 3000:80 >/dev/null 2>&1 &
    kubectl -n $NS port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
    kubectl -n $NS port-forward svc/kps-kube-prometheus-stack-alertmanager 9093:9093 >/dev/null 2>&1 &
    trap 'kill 0' INT TERM; wait ;;
  password)
    echo "admin / $(kubectl -n $NS get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)" ;;
  targets)
    curl -fsS localhost:9090/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
for t in json.load(sys.stdin)['data']['activeTargets']:
    l=t['labels']; print(f\"{t['health']:5s} {l.get('namespace','-'):12s} {l.get('job','?'):40s} {t.get('lastError','')[:60]}\")" | sort || die "Prometheus not reachable on localhost:9090 — run '$0 open' first" ;;
  destroy)
    read -r -p "Uninstall the monitoring stack (namespace $NS)? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] || { echo aborted; exit 0; }
    helm uninstall kps -n $NS || true
    kubectl delete -f "$MAN/servicemonitors.yaml" -f "$MAN/rules.yaml" -f "$MAN/dashboard-configmap.yaml" --ignore-not-found
    kubectl delete crd -l app.kubernetes.io/name=kube-prometheus-stack --ignore-not-found 2>/dev/null || true   # CRDs are NOT removed by helm uninstall
    kubectl delete namespace $NS --wait=false; ok "removed" ;;
  *) die "usage: $0 deploy | status | open | password | targets | destroy" ;;
esac
