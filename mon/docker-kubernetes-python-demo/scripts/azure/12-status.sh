#!/usr/bin/env bash
# What exists in Azure right now (and what it might cost you).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env
az resource list -g "$AZ_RESOURCE_GROUP" --query '[].{name:name, type:type, location:location}' -o table 2>/dev/null || warn "resource group $AZ_RESOURCE_GROUP not found"
echo; log "Estimated monthly cost drivers: AKS nodes (per VM), VM, LoadBalancer public IP, ACR Basic (~\$5). Free tier control plane is \$0."
echo "  az consumption usage list is subscription-wide; the Azure Portal 'Cost analysis' filtered by tag project=$APP_NAME is easiest."
