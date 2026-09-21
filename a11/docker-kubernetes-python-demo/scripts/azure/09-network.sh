#!/usr/bin/env bash
# Azure phase 9 — network access control at three layers:
#   pods  : Kubernetes NetworkPolicy (Cilium)              -> ./09-network.sh policies
#   cloud : Azure NSG rules on the node subnet + LB        -> ./09-network.sh nsg
#   edge  : only allow YOUR IP to reach the public service -> ./09-network.sh lock-to-me | unlock
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env registry
mapfile -t VALUES < <(helm_values_args)
case "${1:-policies}" in
  policies) "$ROOT/scripts/09-network.sh" show; "$ROOT/scripts/09-network.sh" test ;;
  nsg)
    noderg="$(az aks show -g "$AZ_RESOURCE_GROUP" -n "$AZ_AKS_NAME" --query nodeResourceGroup -o tsv)"
    log "NSGs in the AKS node resource group $noderg (Azure manages these; LoadBalancer services add rules automatically)"
    for nsg in $(az network nsg list -g "$noderg" --query '[].name' -o tsv); do
      az network nsg rule list -g "$noderg" --nsg-name "$nsg" --include-default -o table --query '[?direction==`Inbound`].{name:name, prio:priority, access:access, port:destinationPortRange, src:sourceAddressPrefix}'
    done ;;
  lock-to-me)
    myip="$(curl -fsS https://api.ipify.org)"
    log "restricting the public LoadBalancer to $myip/32 (loadBalancerSourceRanges -> Azure LB + NSG)"
    helm upgrade "$APP_NAME" "$ROOT/helm/python-demo" -n "$APP_NAMESPACE" "${VALUES[@]}" \
      --set publicServiceType=LoadBalancer --set "publicServiceSourceRanges={$myip/32}" --wait
    ok "only $myip can reach the web service now" ;;
  unlock)
    helm upgrade "$APP_NAME" "$ROOT/helm/python-demo" -n "$APP_NAMESPACE" "${VALUES[@]}" \
      --set publicServiceType=LoadBalancer --set 'publicServiceSourceRanges=null' --wait
    ok "public again" ;;
  *) die "usage: $0 policies | nsg | lock-to-me | unlock" ;;
esac
