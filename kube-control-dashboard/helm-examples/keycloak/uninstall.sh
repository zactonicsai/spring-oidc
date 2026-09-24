#!/usr/bin/env bash
set -Eeuo pipefail
NAMESPACE="${NAMESPACE:-keycloak}"
RELEASE="${RELEASE:-keycloak}"
helm uninstall "$RELEASE" -n "$NAMESPACE" || true
echo "Helm release removed. The namespace/PVCs may still contain data."
echo "Review before deleting: kubectl get all,pvc -n $NAMESPACE"
