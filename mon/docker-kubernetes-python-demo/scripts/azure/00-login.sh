#!/usr/bin/env bash
# Azure phase 0 — sign in, pick the subscription, register the resource providers we need.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require az
if ! az account show >/dev/null 2>&1; then
  log "az login (a browser window opens; use 'az login --use-device-code' on a headless machine)"
  az login >/dev/null
fi
if [[ -n "${AZ_SUBSCRIPTION:-}" ]]; then az account set --subscription "$AZ_SUBSCRIPTION"; fi
az account show --query '{subscription:name, id:id, tenant:tenantId, user:user.name}' -o table
log "Registering resource providers (one-time per subscription; safe to repeat)"
for ns in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.Compute Microsoft.Network Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.OperationalInsights; do
  az provider register --namespace "$ns" --wait >/dev/null && ok "$ns"
done
log "kubectl + kubelogin (installed by az if missing)"
command -v kubectl >/dev/null || az aks install-cli
ok "logged in. Optional: put AZ_SUBSCRIPTION=<name-or-id> and AZ_LOCATION=<region> in .env"
