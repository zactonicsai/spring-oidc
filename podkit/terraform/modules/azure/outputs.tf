output "cluster" {
  description = "Connection details of the existing cluster for the kubernetes provider."
  value = {
    host               = local.kube.host
    ca_certificate     = base64decode(local.kube.cluster_ca_certificate)
    client_certificate = base64decode(local.kube.client_certificate)
    client_key         = base64decode(local.kube.client_key)
    token              = null
  }
  sensitive = true
}

output "service_account_annotations" {
  value = var.create_identity ? { "azure.workload.identity/client-id" = one(azurerm_user_assigned_identity.this[*].client_id) } : {}
}

output "pod_labels" {
  # The workload identity webhook only mutates pods carrying this label.
  value = var.create_identity ? { "azure.workload.identity/use" = "true" } : {}
}

output "node_selector" {
  value = var.spot ? { "kubernetes.azure.com/scalesetpriority" = "spot" } : {}
}

output "tolerations" {
  value = var.spot ? [{
    key      = "kubernetes.azure.com/scalesetpriority"
    operator = "Equal"
    value    = "spot"
    effect   = "NoSchedule"
  }] : []
}

output "secret_values" {
  description = "ENV_VAR => secret value (stored in the state: use an encrypted backend)."
  value       = { for k, v in data.azurerm_key_vault_secret.this : k => v.value }
  sensitive   = true
}

output "identity_id" {
  description = "Client id of the managed identity bound to the ServiceAccount (null when create_identity is false)."
  value       = one(azurerm_user_assigned_identity.this[*].client_id)
}
