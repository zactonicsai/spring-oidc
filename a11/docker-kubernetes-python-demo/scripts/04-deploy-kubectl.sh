#!/usr/bin/env bash
# Phase 4 (alternative) — deploy the raw YAML in k8s/ with kubectl (no Helm).
# Do NOT run this while the Helm release is installed: same object names.
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
if helm status "$APP_NAME" -n "$APP_NAMESPACE" >/dev/null 2>&1; then
  die "Helm release '$APP_NAME' exists. Run: helm uninstall $APP_NAME -n $APP_NAMESPACE   first."
fi
log "Applying k8s/*.yaml"
kubectl apply -f "$ROOT/k8s/namespace.yaml"
kubectl apply -f "$ROOT/k8s/configmap.yaml"
if [[ -f "$ROOT/secrets.env" ]]; then
  # kubectl builds the Secret from the env file — values never touch git
  kubectl -n "$APP_NAMESPACE" create secret generic "$APP_NAME-api-secrets" \
    --from-env-file="$ROOT/secrets.env" --dry-run=client -o yaml | kubectl apply -f -
else
  warn "secrets.env not found — applying the example secret (empty token)"
  kubectl apply -f "$ROOT/k8s/secret.example.yaml"
fi
kubectl apply -f "$ROOT/k8s/web.yaml" -f "$ROOT/k8s/api.yaml"
kubectl apply -f "$ROOT/k8s/hpa.yaml"
[[ "$NETWORK_POLICY_ENABLED" == "true" ]] && kubectl apply -f "$ROOT/k8s/network-policy.yaml"
for svc in $SERVICES; do wait_for_rollout "$APP_NAMESPACE" "$(svc_var "$svc" K8S_NAME)"; done
kubectl -n "$APP_NAMESPACE" get deploy,svc,hpa,networkpolicy
