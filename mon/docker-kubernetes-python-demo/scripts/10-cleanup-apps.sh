#!/usr/bin/env bash
# Remove only the application (keep the cluster).
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
helm uninstall "$APP_NAME" -n "$APP_NAMESPACE" 2>/dev/null || true
kubectl delete -f "$ROOT/k8s/" --ignore-not-found 2>/dev/null || true
kubectl delete namespace "$APP_NAMESPACE" --ignore-not-found
ok "application removed; cluster still running"
