output "deployment_name" {
  value = kubernetes_deployment_v1.this.metadata[0].name
}

output "service_account" {
  value = kubernetes_service_account_v1.this.metadata[0].name
}

output "service_name" {
  value = try(kubernetes_service_v1.this[0].metadata[0].name, null)
}

output "service_dns" {
  description = "In-cluster DNS name of the Service (null when no Service is created)."
  value       = try("${kubernetes_service_v1.this[0].metadata[0].name}.${var.namespace}.svc.cluster.local", null)
}
