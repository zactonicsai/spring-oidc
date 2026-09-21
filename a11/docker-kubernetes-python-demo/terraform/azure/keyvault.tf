# Key Vault: where secret VALUES live in Azure. RBAC mode (no legacy access policies).
resource "azurerm_key_vault" "kv" {
  count                      = local.create_kv ? 1 : 0
  name                       = local.kv_name # 3-24 chars, globally unique
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # keep false for a learning project so destroy is clean
  tags                       = local.tags
}

# Whoever runs terraform may read/write secrets
resource "azurerm_role_assignment" "kv_officer_me" {
  count                = local.create_kv ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The AKS Key Vault CSI addon identity may read secrets (for SecretProviderClass, see docs)
resource "azurerm_role_assignment" "kv_reader_aks_csi" {
  count                = local.create_kv ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_identity[0].object_id
}

# One Key Vault secret per KEY passed in var.secrets (names use dashes: API_TOKEN -> API-TOKEN)
resource "azurerm_key_vault_secret" "app" {
  for_each     = local.create_kv ? var.secrets : {}
  name         = replace(each.key, "_", "-")
  value        = each.value
  key_vault_id = azurerm_key_vault.kv[0].id
  content_type = "text/plain"
  depends_on   = [azurerm_role_assignment.kv_officer_me] # RBAC must exist before we can write
}
