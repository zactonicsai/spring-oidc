#!/usr/bin/env bash
# Point kubectl at an existing EKS, AKS or GKE cluster.
#
#   cluster-login.sh -p aws   -c CLUSTER -r REGION
#   cluster-login.sh -p azure -c CLUSTER -g RESOURCE_GROUP
#   cluster-login.sh -p gcp   -c CLUSTER -P PROJECT -l LOCATION
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() { sed -n '2,7p' "${BASH_SOURCE[0]}"; exit "${1:-0}"; }

provider="" cluster="" region="" group="" project="" location=""
while getopts ":p:c:r:g:P:l:h" opt; do
  case $opt in
    p) provider=$OPTARG ;; c) cluster=$OPTARG ;; r) region=$OPTARG ;; g) group=$OPTARG ;;
    P) project=$OPTARG ;; l) location=$OPTARG ;; h) usage ;; *) usage 1 ;;
  esac
done
[[ -n "$provider" && -n "$cluster" ]] || usage 1

case "$provider" in
  aws)
    require_cmd aws kubectl
    [[ -n "$region" ]] || die "-r REGION is required for aws"
    aws eks update-kubeconfig --name "$cluster" --region "$region" ;;
  azure)
    require_cmd az kubectl
    [[ -n "$group" ]] || die "-g RESOURCE_GROUP is required for azure"
    az aks get-credentials --resource-group "$group" --name "$cluster" --overwrite-existing
    # Entra ID integrated clusters need kubelogin to turn the kubeconfig into a non-interactive one.
    if command -v kubelogin >/dev/null 2>&1; then kubelogin convert-kubeconfig -l azurecli; fi ;;
  gcp)
    require_cmd gcloud kubectl
    [[ -n "$project" && -n "$location" ]] || die "-P PROJECT and -l LOCATION are required for gcp"
    gcloud container clusters get-credentials "$cluster" --location "$location" --project "$project" ;;
  *) die "unknown provider: $provider (aws|azure|gcp)" ;;
esac

log "kubectl context is now: $(current_context)"
kube version >/dev/null && kube get nodes -o wide | head -n 5
