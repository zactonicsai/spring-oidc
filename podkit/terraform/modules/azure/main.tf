# Azure (AKS): reads the existing cluster, resolves Key Vault secrets and optionally creates a
# user-assigned managed identity federated with the pod's ServiceAccount (Workload Identity).

terraform {
  required_version = ">= 1.3"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
  }
}

data "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

locals {
  # Prefer the certificate-based admin kubeconfig (local accounts enabled); otherwise fall back to the
  # user kubeconfig, which on Entra-ID-only clusters needs kubelogin exec auth in the provider block.
  kube_admin = try(data.azurerm_kubernetes_cluster.this.kube_admin_config[0], null)
  kube_user  = data.azurerm_kubernetes_cluster.this.kube_config[0]
  kube       = local.kube_admin != null && try(local.kube_admin.client_certificate, "") != "" ? local.kube_admin : local.kube_user

  kv_rg    = coalesce(var.key_vault_resource_group_name, var.resource_group_name)
  read_kv  = var.key_vault_name != null
  identity = var.create_identity ? "id-${var.cluster_name}-${var.namespace}-${var.name}" : null
  tags     = merge({ "podkit-workload" = "${var.namespace}/${var.name}", "podkit-cluster" = var.cluster_name }, var.tags)
}

# ---- secrets ------------------------------------------------------------------------------------

data "azurerm_key_vault" "this" {
  count               = local.read_kv ? 1 : 0
  name                = var.key_vault_name
  resource_group_name = local.kv_rg
}

data "azurerm_key_vault_secret" "this" {
  for_each     = local.read_kv ? var.secrets : {}
  name         = each.value
  key_vault_id = data.azurerm_key_vault.this[0].id
}

# ---- identity -----------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "this" {
  count               = var.create_identity ? 1 : 0
  name                = local.identity
  location            = data.azurerm_kubernetes_cluster.this.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "this" {
  count               = var.create_identity ? 1 : 0
  name                = "${var.namespace}-${var.service_account_name}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

# Vault must use "Azure role-based access control"; for the legacy access-policy model use
# azurerm_key_vault_access_policy with secret_permissions = ["Get", "List"] instead.
resource "azurerm_role_assignment" "key_vault" {
  count                = var.create_identity && local.read_kv && length(var.secrets) > 0 ? 1 : 0
  scope                = data.azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this[0].principal_id
}

resource "azurerm_role_assignment" "extra" {
  for_each             = var.create_identity ? { for i, ra in var.extra_role_assignments : tostring(i) => ra } : {}
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.this[0].principal_id
}
