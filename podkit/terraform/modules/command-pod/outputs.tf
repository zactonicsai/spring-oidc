output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "deployment_name" {
  value = kubernetes_deployment_v1.this.metadata[0].name
}

output "selector" {
  description = "Label selector for kubectl exec / cp."
  value       = "app.kubernetes.io/name=${var.name}"
}
