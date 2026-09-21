#!/usr/bin/env bash
# Delete EVERYTHING this project created in Azure (the whole resource group). Irreversible.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env
read -r -p "Delete resource group $AZ_RESOURCE_GROUP and everything in it? [y/N] " a
[[ "$a" =~ ^[Yy]$ ]] || { echo "aborted"; exit 0; }
az group delete --name "$AZ_RESOURCE_GROUP" --yes --no-wait
kubectl config delete-context "$AZ_AKS_NAME" 2>/dev/null || true
kubectl config delete-cluster "$AZ_AKS_NAME" 2>/dev/null || true
# Key Vault soft-delete keeps the name reserved for 90 days unless purged:
[[ "$AZ_KEYVAULT_ENABLED" == "true" ]] && az keyvault purge --name "$AZ_KEYVAULT_NAME" --no-wait 2>/dev/null || true
ok "deletion started (runs in the background; check with 12-status.sh)"
