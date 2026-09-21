#!/usr/bin/env bash
# Phase 4 (recommended) — deploy with Helm using values rendered from app.config.yaml.
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
CHART="$ROOT/helm/python-demo"
mapfile -t VALUES < <(helm_values_args)

log "helm lint"
helm lint "$CHART" "${VALUES[@]}"
log "helm upgrade --install $APP_NAME (namespace $APP_NAMESPACE)"
# Helm 4: --wait uses kstatus (waits until every resource is truly Ready)
helm upgrade --install "$APP_NAME" "$CHART" \
  --namespace "$APP_NAMESPACE" --create-namespace \
  "${VALUES[@]}" \
  --wait --timeout 3m
ok "release '$APP_NAME' deployed"
kubectl -n "$APP_NAMESPACE" get deploy,svc,hpa,networkpolicy
