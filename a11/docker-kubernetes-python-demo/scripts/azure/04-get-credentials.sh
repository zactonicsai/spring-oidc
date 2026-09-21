#!/usr/bin/env bash
# Azure phase 4 — download the kubeconfig so kubectl/helm talk to AKS instead of kind.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env
az aks get-credentials --resource-group "$AZ_RESOURCE_GROUP" --name "$AZ_AKS_NAME" --overwrite-existing
kubectl config current-context
kubectl get nodes -o wide
ok "kubectl now points at AKS. Switch back to kind any time:  kubectl config use-context kind-$KIND_CLUSTER_NAME"
