output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}

output "next_steps" {
  value = <<-EOT
    kubectl config use-context kind-${kind_cluster.this.name}
    kubectl -n ${module.app.namespace} get pods,svc,hpa,networkpolicy
    ${join("\n    ", [for n in module.app.public_service_names : "kubectl -n ${module.app.namespace} port-forward svc/${module.app.services[n].k8s_name} 8080:${module.app.services[n].ports[0].service_port}   # ${n}"])}
    helm test ${local.name} -n ${module.app.namespace}
  EOT
}
