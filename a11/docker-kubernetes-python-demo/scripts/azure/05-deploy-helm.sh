#!/usr/bin/env bash
# Azure phase 5 — same Helm chart, same app.config.yaml; only two things change:
#   1. images are pulled from ACR  (global.imageRegistry = <acr>.azurecr.io)
#   2. "public" services become type LoadBalancer so Azure hands out a public IP
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env registry
kubectl config current-context | grep -q "$AZ_AKS_NAME" || die "kubectl is not pointing at $AZ_AKS_NAME — run 04-get-credentials.sh"
mapfile -t VALUES < <(helm_values_args)
CHART="$ROOT/helm/python-demo"
helm lint "$CHART" "${VALUES[@]}" >/dev/null && ok "chart lint OK"
log "helm upgrade --install $APP_NAME (images from $ACR_LOGIN_SERVER)"
helm upgrade --install "$APP_NAME" "$CHART" \
  --namespace "$APP_NAMESPACE" --create-namespace \
  "${VALUES[@]}" \
  --set publicServiceType=LoadBalancer \
  --wait --timeout 5m
kubectl -n "$APP_NAMESPACE" get deploy,hpa,networkpolicy
log "waiting for Azure to assign a public IP to the LoadBalancer service(s)"
for svc in $PUBLIC_SERVICES; do
  name="$(svc_var "$svc" K8S_NAME)"
  for _ in $(seq 1 60); do ip="$(public_ip_of_service "$name")"; [[ -n "$ip" ]] && break; sleep 5; done
  [[ -n "${ip:-}" ]] && ok "$svc -> http://$ip:$(svc_var "$svc" PORT)" || warn "$svc has no public IP yet: kubectl -n $APP_NAMESPACE get svc -w"
done
