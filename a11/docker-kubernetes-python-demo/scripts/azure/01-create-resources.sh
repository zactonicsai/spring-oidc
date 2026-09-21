#!/usr/bin/env bash
# Azure phase 1 — resource group + container registry (ACR).
#   Resource group = the shopping bag: delete it and everything inside is gone.
#   ACR            = the warehouse that stores your container images.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env
log "resource group $AZ_RESOURCE_GROUP in $AZ_LOCATION"
az group create --name "$AZ_RESOURCE_GROUP" --location "$AZ_LOCATION" --tags "${TAGS[@]}" -o none
ok "resource group ready"
log "container registry $AZ_ACR_NAME (Basic tier ≈ cheapest; Premium adds geo-replication + private link)"
if az acr show -n "$AZ_ACR_NAME" -g "$AZ_RESOURCE_GROUP" >/dev/null 2>&1; then
  ok "ACR exists"
else
  az acr check-name --name "$AZ_ACR_NAME" --query nameAvailable -o tsv | grep -q true || die "ACR name '$AZ_ACR_NAME' is taken: set AZ_ACR_NAME_OVERRIDE=<letters+digits> in .env"
  az acr create --resource-group "$AZ_RESOURCE_GROUP" --name "$AZ_ACR_NAME" --sku Basic \
    --admin-enabled false --tags "${TAGS[@]}" -o none         # no admin user: identities pull, not passwords
  ok "ACR created: $ACR_LOGIN_SERVER"
fi
az acr show -n "$AZ_ACR_NAME" --query '{name:name, loginServer:loginServer, sku:sku.name, location:location}' -o table
