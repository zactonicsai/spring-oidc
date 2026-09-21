resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.aks_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${local.name}-${local.suffix}"
  kubernetes_version  = local.k8s_version # null = AKS default GA version
  sku_tier            = local.az.aks_tier == "standard" ? "Standard" : "Free"

  oidc_issuer_enabled       = true # workload identity: pods get Azure identities, no secrets
  workload_identity_enabled = true

  default_node_pool {
    name                 = "system"
    vm_size              = local.az.aks_vm_size
    node_count           = local.az.aks_node_count
    auto_scaling_enabled = local.az.aks_autoscale
    min_count            = local.az.aks_autoscale ? local.az.aks_min_count : null
    max_count            = local.az.aks_autoscale ? local.az.aks_max_count : null
    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Azure CNI Overlay + Cilium dataplane = Microsoft's recommended setup; enforces NetworkPolicy with eBPF.
  # (Azure NPM is being retired: Windows Sept 2026, Linux Sept 2028.)
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = local.aks_net == "cilium" ? "cilium" : "azure"
    network_policy      = local.aks_net
  }

  # CSI driver that can mount Key Vault secrets straight into pods
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = local.tags

  lifecycle {
    # the autoscaler changes node_count at runtime; don't fight it on the next apply
    ignore_changes = [default_node_pool[0].node_count]
  }
}

# Let the cluster's kubelet identity pull from ACR (same as `az aks create --attach-acr`)
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
