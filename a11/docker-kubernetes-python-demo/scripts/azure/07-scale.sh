#!/usr/bin/env bash
# Azure phase 7 — two kinds of scaling:
#   PODS  (inside the cluster)  : HPA already installed by the chart; or kubectl scale
#   NODES (the machines)        : cluster autoscaler adds VMs when pods don't fit; or az aks scale
#   ./07-scale.sh pods web 4 | nodes 3 | autoscaler 1 5 | load 90 | status
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env
POOL="$(az aks nodepool list -g "$AZ_RESOURCE_GROUP" --cluster-name "$AZ_AKS_NAME" --query '[0].name' -o tsv)"
case "${1:-status}" in
  pods)   kubectl -n "$APP_NAMESPACE" scale "deployment/$(svc_var "${2:?svc}" K8S_NAME)" --replicas="${3:?n}"
          warn "if an HPA manages this deployment it will move the count back into [min,max] within a minute" ;;
  nodes)  log "manual node scale (only works when the autoscaler is OFF)"
          az aks scale -g "$AZ_RESOURCE_GROUP" -n "$AZ_AKS_NAME" --nodepool-name "$POOL" --node-count "${2:?n}" -o none && kubectl get nodes ;;
  autoscaler) az aks update -g "$AZ_RESOURCE_GROUP" -n "$AZ_AKS_NAME" --update-cluster-autoscaler --min-count "${2:?min}" --max-count "${3:?max}" -o none
          ok "cluster autoscaler range set to ${2}-${3} nodes" ;;
  load)   "$ROOT/scripts/07-scale.sh" load "${2:-90}" ;;   # same HPA demo as local: hammers api /api/work
  status) az aks nodepool show -g "$AZ_RESOURCE_GROUP" --cluster-name "$AZ_AKS_NAME" -n "$POOL" \
            --query '{pool:name, count:count, min:minCount, max:maxCount, autoscale:enableAutoScaling, size:vmSize}' -o table
          kubectl get nodes; kubectl -n "$APP_NAMESPACE" get hpa; kubectl -n "$APP_NAMESPACE" top pods 2>/dev/null || true ;;
  *) die "usage: $0 pods <svc> <n> | nodes <n> | autoscaler <min> <max> | load [sec] | status" ;;
esac
