#!/usr/bin/env bash
# Azure phase 8 — secrets the cloud way: values live in Key Vault, never in files or git.
#   ./08-secrets.sh create                  # Key Vault + RBAC role for you
#   ./08-secrets.sh set API_TOKEN <value>   # store/rotate a secret in Key Vault
#   ./08-secrets.sh deploy                  # pull values from Key Vault -> Kubernetes Secret via helm (checksum restarts pods)
#   ./08-secrets.sh csi                     # print a SecretProviderClass to mount Key Vault secrets directly (production pattern)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env registry
[[ "$AZ_KEYVAULT_ENABLED" == "true" ]] || die "targets.azure.keyVault.enabled is false in app.config.yaml"
case "${1:-create}" in
  create)
    if az keyvault show -n "$AZ_KEYVAULT_NAME" >/dev/null 2>&1; then ok "Key Vault $AZ_KEYVAULT_NAME exists"; else
      log "creating Key Vault $AZ_KEYVAULT_NAME (RBAC mode)"
      az keyvault create -n "$AZ_KEYVAULT_NAME" -g "$AZ_RESOURCE_GROUP" -l "$AZ_LOCATION" --enable-rbac-authorization true --tags "${TAGS[@]}" -o none
    fi
    me="$(az ad signed-in-user show --query id -o tsv)"; scope="$(az keyvault show -n "$AZ_KEYVAULT_NAME" --query id -o tsv)"
    az role assignment create --role "Key Vault Secrets Officer" --assignee-object-id "$me" --assignee-principal-type User --scope "$scope" -o none 2>/dev/null || true
    ok "you can now read/write secrets in $AZ_KEYVAULT_NAME (RBAC can take ~1 min to apply)" ;;
  set)
    key="${2:?KEY}"; val="${3:?value}"
    az keyvault secret set --vault-name "$AZ_KEYVAULT_NAME" --name "${key//_/-}" --value "$val" -o none   # KV names use dashes, not underscores
    ok "stored ${key//_/-} in Key Vault (version: $(az keyvault secret show --vault-name "$AZ_KEYVAULT_NAME" -n "${key//_/-}" --query 'id' -o tsv | awk -F/ '{print $NF}'))" ;;
  deploy)
    : > "$ROOT/secrets.env"; chmod 600 "$ROOT/secrets.env"
    for svc in $SERVICES; do for key in $(svc_var "$svc" SECRET_KEYS); do
      val="$(az keyvault secret show --vault-name "$AZ_KEYVAULT_NAME" -n "${key//_/-}" --query value -o tsv)" || die "secret ${key//_/-} not in Key Vault (run: $0 set $key <value>)"
      printf '%s=%s\n' "$key" "$val" >> "$ROOT/secrets.env"
    done; done
    ok "pulled $(wc -l < "$ROOT/secrets.env") secret(s) from Key Vault into secrets.env (git-ignored, mode 600)"
    "$ROOT/scripts/azure/05-deploy-helm.sh"
    rm -f "$ROOT/secrets.env"; ok "secrets.env removed again — Key Vault stays the source of truth" ;;
  csi)
    tenant="$(az account show --query tenantId -o tsv)"
    client="$(az aks show -g "$AZ_RESOURCE_GROUP" -n "$AZ_AKS_NAME" --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)"
    cat <<YAML
# Production pattern: the Secrets Store CSI driver mounts Key Vault secrets into the pod and can
# sync them into a Kubernetes Secret. No values ever pass through your laptop.
# 1) az role assignment create --role "Key Vault Secrets User" --assignee $client --scope \$(az keyvault show -n $AZ_KEYVAULT_NAME --query id -o tsv)
# 2) kubectl apply -f - <<EOF  (this file)
# 3) add to the pod: volumes[csi.driver=secrets-store.csi.k8s.io, secretProviderClass=$APP_NAME-kv]
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata: { name: $APP_NAME-kv, namespace: $APP_NAMESPACE }
spec:
  provider: azure
  parameters:
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "$client"
    keyvaultName: "$AZ_KEYVAULT_NAME"
    tenantId: "$tenant"
    objects: |
      array:
        - |
          objectName: API-TOKEN
          objectType: secret
  secretObjects:
    - secretName: $(svc_var api K8S_NAME)-secrets
      type: Opaque
      data: [{ objectName: API-TOKEN, key: API_TOKEN }]
YAML
    ;;
  *) die "usage: $0 create | set KEY value | deploy | csi" ;;
esac
