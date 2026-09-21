output "resource_group" { value = azurerm_resource_group.rg.name }
output "acr_login_server" { value = azurerm_container_registry.acr.login_server }
output "aks_name" { value = azurerm_kubernetes_cluster.aks.name }
output "aks_kubernetes_version" { value = azurerm_kubernetes_cluster.aks.kubernetes_version }
output "key_vault_name" { value = local.create_kv ? azurerm_key_vault.kv[0].name : null }
output "vm_public_ip" { value = local.create_vm ? azurerm_public_ip.vm[0].ip_address : null }

output "next_steps" {
  value = <<-EOT
    az aks get-credentials -g ${azurerm_resource_group.rg.name} -n ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing
    kubectl -n ${module.app.namespace} get pods,svc,hpa,networkpolicy
    kubectl -n ${module.app.namespace} get svc -w      # wait for the LoadBalancer EXTERNAL-IP
    ${local.create_vm ? "ssh ${module.cfg.hosts.admin_user}@${azurerm_public_ip.vm[0].ip_address} sudo tail -f /var/log/cloud-init-output.log" : "# VM disabled (targets.azure.vm.enabled)"}
  EOT
}
