#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-keycloak}"
RELEASE="${RELEASE:-keycloak}"
CHART="${CHART:-oci://registry-1.docker.io/bitnamicharts/keycloak}"
# Snapshot used when this example was prepared. Override when you intentionally
# test a newer chart: KEYCLOAK_CHART_VERSION=x.y.z ./install-local.sh
KEYCLOAK_CHART_VERSION="${KEYCLOAK_CHART_VERSION:-25.4.0}"
ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-change-me-now}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }
command -v helm >/dev/null || { echo "helm is required" >&2; exit 1; }

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create secret generic keycloak-admin \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Keycloak chart $KEYCLOAK_CHART_VERSION into namespace $NAMESPACE..."
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --version "$KEYCLOAK_CHART_VERSION" \
  -f "$SCRIPT_DIR/values-local.yaml" \
  --wait \
  --timeout 10m

echo
echo "Keycloak is installed. Useful checks:"
echo "  kubectl get pods,svc -n $NAMESPACE"
echo "  helm status $RELEASE -n $NAMESPACE"
echo
echo "Port-forward it with:"
echo "  kubectl -n $NAMESPACE port-forward svc/$RELEASE 8080:80"
echo
echo "Then create the OIDC demo realm/client with:"
echo "  KEYCLOAK_ADMIN_PASSWORD='***' $SCRIPT_DIR/configure-demo-realm.sh"
