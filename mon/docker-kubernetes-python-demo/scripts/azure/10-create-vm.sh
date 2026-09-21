#!/usr/bin/env bash
# Azure phase 10 — a plain Linux VM configured from app.config.yaml (the "no Kubernetes" path).
#   cloud-init (rendered from the schema) drops setup.sh + configure.sh on the box and runs them at first boot:
#   packages, docker, ufw ports, admin user, downloaded files, settings, and the app containers pulled from ACR.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env registry
[[ "$AZ_VM_ENABLED" == "true" ]] || die "targets.azure.vm.enabled is false"
python3 "$ROOT/tools/appconfig.py" render cloudinit -c "$CONFIG_FILE" -o "$BUILD_DIR" --registry "$ACR_LOGIN_SERVER" >/dev/null
ok "rendered build/cloud-init.yaml ($(wc -c < "$BUILD_DIR/cloud-init.yaml") bytes; Azure limit is 64 KB)"

if az vm show -g "$AZ_RESOURCE_GROUP" -n "$AZ_VM_NAME" >/dev/null 2>&1; then ok "VM $AZ_VM_NAME exists"; else
  log "az vm create $AZ_VM_NAME ($AZ_VM_IMAGE, $AZ_VM_SIZE) with a system-assigned managed identity"
  az vm create -g "$AZ_RESOURCE_GROUP" -n "$AZ_VM_NAME" -l "$AZ_LOCATION" \
    --image "$AZ_VM_IMAGE" --size "$AZ_VM_SIZE" \
    --admin-username "$AZ_VM_ADMIN_USER" --generate-ssh-keys \
    --assign-identity '[system]' \
    --public-ip-sku Standard --nsg-rule NONE \
    --custom-data "$BUILD_DIR/cloud-init.yaml" \
    --tags "${TAGS[@]}" -o none
fi
log "opening NSG ports from hosts.exposePorts: $HOST_PORTS"
prio=1000
for p in $HOST_PORTS; do
  port="${p%%/*}"; proto="${p##*/}"
  az vm open-port -g "$AZ_RESOURCE_GROUP" -n "$AZ_VM_NAME" --port "$port" --priority "$prio" -o none && ok "$proto/$port allowed (priority $prio)"
  prio=$((prio+10))
done
log "AcrPull for the VM identity (so configure.sh can docker pull from $ACR_LOGIN_SERVER without a password)"
vm_id="$(az vm show -g "$AZ_RESOURCE_GROUP" -n "$AZ_VM_NAME" --query identity.principalId -o tsv)"
acr_id="$(az acr show -n "$AZ_ACR_NAME" --query id -o tsv)"
az role assignment create --role AcrPull --assignee-object-id "$vm_id" --assignee-principal-type ServicePrincipal --scope "$acr_id" -o none 2>/dev/null || true
ip="$(az vm show -d -g "$AZ_RESOURCE_GROUP" -n "$AZ_VM_NAME" --query publicIps -o tsv)"
ok "VM public IP: $ip"
echo "  ssh $AZ_VM_ADMIN_USER@$ip                             # log in"
echo "  ssh $AZ_VM_ADMIN_USER@$ip sudo tail -f /var/log/cloud-init-output.log   # watch setup/configure run"
echo "  curl http://$ip/                                       # the web app, once configure.sh finished (~3 min)"
echo "  az vm run-command invoke -g $AZ_RESOURCE_GROUP -n $AZ_VM_NAME --command-id RunShellScript --scripts 'cat /etc/$APP_NAME/config.env; docker ps'"
