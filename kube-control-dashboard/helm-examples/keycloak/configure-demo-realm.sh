#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-keycloak}"
REALM="${REALM:-k8s-demo}"
CLIENT_ID="${CLIENT_ID:-k8s-webapp}"
REDIRECT_URI="${REDIRECT_URI:-http://localhost:8088/*}"
WEB_ORIGIN="${WEB_ORIGIN:-http://localhost:8088}"
ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  cat >&2 <<'MSG'
Set KEYCLOAK_ADMIN_PASSWORD first, for example:
  KEYCLOAK_ADMIN_PASSWORD='change-me-now' ./configure-demo-realm.sh
MSG
  exit 1
fi

POD="$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$POD" ]] || { echo "No Keycloak pod found in namespace $NAMESPACE" >&2; exit 1; }

echo "Using Keycloak pod: $POD"

# The Bitnami image currently places Keycloak under /opt/bitnami/keycloak.
# Find kcadm.sh instead of assuming one exact path.
kubectl -n "$NAMESPACE" exec "$POD" -- env \
  DEMO_ADMIN_USER="$ADMIN_USER" \
  DEMO_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  DEMO_REALM="$REALM" \
  DEMO_CLIENT_ID="$CLIENT_ID" \
  DEMO_REDIRECT_URI="$REDIRECT_URI" \
  DEMO_WEB_ORIGIN="$WEB_ORIGIN" \
  bash -lc '
set -Eeuo pipefail
KCADM="$(command -v kcadm.sh || true)"
if [[ -z "$KCADM" && -x /opt/bitnami/keycloak/bin/kcadm.sh ]]; then
  KCADM=/opt/bitnami/keycloak/bin/kcadm.sh
fi
[[ -n "$KCADM" ]] || { echo "kcadm.sh not found" >&2; exit 1; }

"$KCADM" config credentials \
  --server http://127.0.0.1:8080 \
  --realm master \
  --user "$DEMO_ADMIN_USER" \
  --password "$DEMO_ADMIN_PASSWORD"

if "$KCADM" get "realms/$DEMO_REALM" >/dev/null 2>&1; then
  echo "Realm $DEMO_REALM already exists"
else
  "$KCADM" create realms \
    -s "realm=$DEMO_REALM" \
    -s enabled=true \
    -s displayName="Kubernetes Demo"
fi

CLIENT_UUID="$("$KCADM" get clients -r "$DEMO_REALM" -q "clientId=$DEMO_CLIENT_ID" --fields id --format csv --noquotes 2>/dev/null | head -n1 || true)"
if [[ -n "$CLIENT_UUID" ]]; then
  echo "Updating client $DEMO_CLIENT_ID"
  "$KCADM" update "clients/$CLIENT_UUID" -r "$DEMO_REALM" \
    -s publicClient=true \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s "redirectUris=[\"$DEMO_REDIRECT_URI\"]" \
    -s "webOrigins=[\"$DEMO_WEB_ORIGIN\"]"
else
  echo "Creating client $DEMO_CLIENT_ID"
  "$KCADM" create clients -r "$DEMO_REALM" \
    -s "clientId=$DEMO_CLIENT_ID" \
    -s name="Kubernetes OIDC Demo Web App" \
    -s enabled=true \
    -s publicClient=true \
    -s protocol=openid-connect \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s "redirectUris=[\"$DEMO_REDIRECT_URI\"]" \
    -s "webOrigins=[\"$DEMO_WEB_ORIGIN\"]"
fi
'

echo
echo "Configured:"
echo "  realm:       $REALM"
echo "  client:      $CLIENT_ID"
echo "  redirect:    $REDIRECT_URI"
echo "  web origin:  $WEB_ORIGIN"
echo
echo "Next: install ./helm-examples/oidc-webapp and create a test user in realm $REALM."
