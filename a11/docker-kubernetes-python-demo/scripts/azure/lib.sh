#!/usr/bin/env bash
# Azure helpers — sourced by every scripts/azure/*.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

azure_env() {
  # $1 = "registry" -> re-render the config with sources.imageRegistry = <acr>.azurecr.io
  require az
  load_config
  az account show >/dev/null 2>&1 || die "not logged in: run ./scripts/azure/00-login.sh"
  AZ_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  # Globally-unique names get a stable 6-char suffix derived from the subscription id.
  # Override any of these in .env (e.g. AZ_ACR_NAME=mycompanyacr) if you prefer.
  AZ_SUFFIX="$(printf '%s' "$AZ_SUBSCRIPTION_ID" | tr -d '-' | cut -c1-6)"
  AZ_ACR_NAME="${AZ_ACR_NAME_OVERRIDE:-${AZ_ACR_NAME}${AZ_SUFFIX}}"
  AZ_KEYVAULT_NAME="${AZ_KEYVAULT_NAME_OVERRIDE:-${AZ_KEYVAULT_NAME}-${AZ_SUFFIX}}"
  ACR_LOGIN_SERVER="${AZ_ACR_NAME}.azurecr.io"
  # shellcheck disable=SC2034
  TAGS=("project=$APP_NAME" "owner=$(cfg owner)" "managed-by=az-cli")
  export AZ_SUBSCRIPTION_ID AZ_ACR_NAME AZ_KEYVAULT_NAME ACR_LOGIN_SERVER
  if [[ "${1:-}" == "registry" ]]; then
    load_config --registry "$ACR_LOGIN_SERVER"      # images become <acr>.azurecr.io/<app>-<svc>:<tag>
    AZ_ACR_NAME="${AZ_ACR_NAME_OVERRIDE:-${AZ_ACR_NAME}${AZ_SUFFIX}}"; ACR_LOGIN_SERVER="${AZ_ACR_NAME}.azurecr.io"
    AZ_KEYVAULT_NAME="${AZ_KEYVAULT_NAME_OVERRIDE:-${AZ_KEYVAULT_NAME}-${AZ_SUFFIX}}"
  fi
}

aks_ready() { az aks show -g "$AZ_RESOURCE_GROUP" -n "$AZ_AKS_NAME" --query provisioningState -o tsv 2>/dev/null | grep -q Succeeded; }
public_ip_of_service() {   # public_ip_of_service <k8s service name>
  kubectl -n "$APP_NAMESPACE" get svc "$1" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null
}
