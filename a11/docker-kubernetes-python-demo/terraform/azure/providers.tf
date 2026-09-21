provider "azurerm" {
  # Auth: `az login` (interactive), or ARM_CLIENT_ID/ARM_CLIENT_SECRET/ARM_TENANT_ID in CI.
  subscription_id = var.subscription_id # or export ARM_SUBSCRIPTION_ID

  # AzureRM 5.0 registers NO resource providers by default (4.x registered ~60 of them).
  # Register only the namespaces this configuration needs — least privilege, faster init.
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.ContainerService",
    "Microsoft.ContainerRegistry",
    "Microsoft.Compute",
    "Microsoft.Network",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
  ]

  features {
    key_vault {
      purge_soft_delete_on_destroy    = true # learning project: really delete the vault on destroy
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# The Helm provider talks to the AKS cluster created in aks.tf.
# (Best practice for production: put Kubernetes-level resources in a SEPARATE Terraform
#  root/state that reads the cluster from a data source. Kept in one root here for simplicity.)
provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}
