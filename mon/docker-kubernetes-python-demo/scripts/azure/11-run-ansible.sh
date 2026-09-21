#!/usr/bin/env bash
# Azure phase 11 — configure the SAME VM with Ansible instead of (or after) the bash scripts.
# Ansible reads app.config.yaml directly (include_vars) — same packages, ports, files and settings.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env registry
require ansible-playbook ssh
ip="$(az vm show -d -g "$AZ_RESOURCE_GROUP" -n "$AZ_VM_NAME" --query publicIps -o tsv)"; [[ -n "$ip" ]] || die "VM not found: run 10-create-vm.sh"
inv="$ROOT/ansible/inventory/azure.ini"
cat > "$inv" <<INI
[app_hosts]
$AZ_VM_NAME ansible_host=$ip ansible_user=$AZ_VM_ADMIN_USER ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
[app_hosts:vars]
image_registry=$ACR_LOGIN_SERVER
INI
ok "inventory written: $inv"
(cd "$ROOT/ansible" && ansible-galaxy collection install -r requirements.yml >/dev/null && \
 ansible-playbook -i "$inv" site.yml -e "image_registry=$ACR_LOGIN_SERVER" "${@}")
