output "cluster" {
  description = "Connection details of the existing cluster for the kubernetes provider."
  value = {
    host               = "https://${data.google_container_cluster.this.endpoint}"
    ca_certificate     = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
    token              = data.google_client_config.this.access_token
    client_certificate = null
    client_key         = null
  }
  sensitive = true
}

output "service_account_annotations" {
  value = var.create_identity ? { "iam.gke.io/gcp-service-account" = one(google_service_account.this[*].email) } : {}
}

output "pod_labels" {
  value = {}
}

output "node_selector" {
  value = var.spot ? { "cloud.google.com/gke-spot" = "true" } : {}
}

output "tolerations" {
  value = var.spot ? [{
    key      = "cloud.google.com/gke-spot"
    operator = "Equal"
    value    = "true"
    effect   = "NoSchedule"
  }] : []
}

output "secret_values" {
  description = "ENV_VAR => secret value (stored in the state: use an encrypted backend)."
  value       = { for k, v in data.google_secret_manager_secret_version.this : k => v.secret_data }
  sensitive   = true
}

output "identity_id" {
  description = "Email of the Google service account bound to the ServiceAccount (null when create_identity is false)."
  value       = one(google_service_account.this[*].email)
}
