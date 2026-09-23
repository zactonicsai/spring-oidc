#!/usr/bin/env bash
# podkit resource: the existing EKS / AKS / GKE cluster (login and status; never created here).
# shellcheck shell=bash

RESOURCE_DESC="Existing cluster: kubeconfig login and status (clusters are never created)"
RESOURCE_VERBS="login status contexts"

resource_usage() {
  cat <<'USAGE'
  podkit cluster login -p aws   -c CLUSTER -r REGION
  podkit cluster login -p azure -c CLUSTER -g RESOURCE_GROUP
  podkit cluster login -p gcp   -c CLUSTER -P PROJECT -l LOCATION
  podkit cluster login BUILD_DIR              settings taken from the build's pod.env
  podkit cluster status                       current context, nodes, podkit footprint
  podkit cluster contexts                     kubectl contexts
USAGE
}

# cluster_login PROVIDER CLUSTER [REGION|RG|PROJECT] [LOCATION]
cluster_login() {
  local provider=$1 cluster=$2 a=${3:-} b=${4:-}
  require_cmd kubectl
  case "$provider" in
    aws)
      require_cmd aws; [[ -n "$a" ]] || die "region is required for aws (-r)"
      run aws eks update-kubeconfig --name "$cluster" --region "$a" ;;
    azure)
      require_cmd az; [[ -n "$a" ]] || die "resource group is required for azure (-g)"
      run az aks get-credentials --resource-group "$a" --name "$cluster" --overwrite-existing
      # Entra ID integrated clusters need kubelogin to make the kubeconfig non-interactive.
      if command -v kubelogin >/dev/null 2>&1; then run kubelogin convert-kubeconfig -l azurecli; fi ;;
    gcp)
      require_cmd gcloud; [[ -n "$a" && -n "$b" ]] || die "project (-P) and location (-l) are required for gcp"
      run gcloud container clusters get-credentials "$cluster" --location "$b" --project "$a" ;;
    *) die "unknown provider: $provider (aws|azure|gcp)" ;;
  esac
  log "kubectl context is now: $(current_context)"
  dry_run || kube get nodes -o wide 2>/dev/null | head -n 6 || true
}

# cluster_login_build BUILD_DIR -> login using pod.env
cluster_login_build() {
  build_load "$1"
  case "$PROVIDER" in
    aws)   cluster_login aws "$CLUSTER_NAME" "$AWS_REGION" ;;
    azure) cluster_login azure "$CLUSTER_NAME" "$AZURE_RESOURCE_GROUP" ;;
    gcp)   cluster_login gcp "$CLUSTER_NAME" "$GCP_PROJECT" "$GCP_LOCATION" ;;
  esac
}

cluster_status() {
  require_cmd kubectl
  echo "context : $(current_context)"
  dry_run && return 0
  kube cluster-info 2>/dev/null | head -n 1 || true
  echo; kube get nodes -o wide 2>/dev/null || true
  echo; echo "podkit workloads:"
  kube get deployments -A -l "$(managed_label)" 2>/dev/null || true
}

cmd_login() {
  if [[ $# -eq 1 && -f "$1/pod.env" ]]; then cluster_login_build "$1"; return; fi
  local provider="" cluster="" region="" group="" project="" location="" OPTIND=1 opt
  while getopts ":p:c:r:g:P:l:" opt; do
    case $opt in
      p) provider=$OPTARG ;; c) cluster=$OPTARG ;; r) region=$OPTARG ;; g) group=$OPTARG ;;
      P) project=$OPTARG ;; l) location=$OPTARG ;; *) die "unknown option -$OPTARG" ;;
    esac
  done
  [[ -n "$provider" && -n "$cluster" ]] || { plugin_usage; exit 1; }
  case "$provider" in
    aws)   cluster_login aws "$cluster" "$region" ;;
    azure) cluster_login azure "$cluster" "$group" ;;
    gcp)   cluster_login gcp "$cluster" "$project" "$location" ;;
    *)     die "unknown provider: $provider" ;;
  esac
}
cmd_status()   { cluster_status; }
cmd_contexts() { require_cmd kubectl; kube config get-contexts; }
