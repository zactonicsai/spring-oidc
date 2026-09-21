#!/usr/bin/env bash
# Azure phase 3 — create the AKS cluster (managed Kubernetes: Azure runs the control plane for you).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env
if aks_ready; then ok "AKS cluster $AZ_AKS_NAME already exists"; exit 0; fi

log "available Kubernetes versions in $AZ_LOCATION (GA only):"
az aks get-versions -l "$AZ_LOCATION" --query 'values[?isPreview==null].{version:version, patches:keys(patchVersions)}' -o table
ver_args=(); [[ -n "$AZ_AKS_K8S_VERSION" ]] && ver_args=(--kubernetes-version "$AZ_AKS_K8S_VERSION")

scale_args=(--node-count "$AZ_AKS_NODE_COUNT")
if [[ "$AZ_AKS_AUTOSCALE" == "true" ]]; then
  scale_args+=(--enable-cluster-autoscaler --min-count "$AZ_AKS_MIN_COUNT" --max-count "$AZ_AKS_MAX_COUNT")
fi

# Network policy engine: Cilium (eBPF) is Microsoft's recommendation; Azure NPM is being retired (Linux: Sept 2028).
case "$AZ_AKS_NETWORK_POLICY" in
  cilium) net_args=(--network-plugin azure --network-plugin-mode overlay --network-dataplane cilium --network-policy cilium) ;;
  azure)  net_args=(--network-plugin azure --network-plugin-mode overlay --network-policy azure) ;;
  calico) net_args=(--network-plugin azure --network-plugin-mode overlay --network-policy calico) ;;
  *) die "unknown targets.azure.aks.networkPolicy: $AZ_AKS_NETWORK_POLICY" ;;
esac

log "az aks create $AZ_AKS_NAME  (this takes ~5-10 minutes)"
az aks create \
  --resource-group "$AZ_RESOURCE_GROUP" --name "$AZ_AKS_NAME" --location "$AZ_LOCATION" \
  --tier "$AZ_AKS_TIER" \
  --node-vm-size "$AZ_AKS_NODE_VM_SIZE" "${scale_args[@]}" \
  "${net_args[@]}" \
  --enable-managed-identity \
  --attach-acr "$AZ_ACR_NAME" \
  --enable-oidc-issuer --enable-workload-identity \
  --enable-addons azure-keyvault-secrets-provider \
  --generate-ssh-keys \
  --tags "${TAGS[@]}" "${ver_args[@]}" -o none
#   --tier free            : no SLA on the control plane (fine for learning; use 'standard' for production)
#   --attach-acr           : gives the cluster's identity AcrPull on the registry -> no image pull secrets
#   --enable-workload-identity : pods can get Azure identities (e.g. to read Key Vault) without secrets
#   --enable-addons azure-keyvault-secrets-provider : CSI driver that mounts Key Vault secrets into pods
ok "AKS cluster created"
az aks show -g "$AZ_RESOURCE_GROUP" -n "$AZ_AKS_NAME" \
  --query '{name:name, version:kubernetesVersion, nodes:agentPoolProfiles[0].count, size:agentPoolProfiles[0].vmSize, policy:networkProfile.networkPolicy, dataplane:networkProfile.networkDataplane, tier:sku.tier}' -o table
