output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}

output "keycloak_admin_username" {
  value = "admin"
}

output "keycloak_admin_password" {
  value     = random_password.keycloak_admin.result
  sensitive = true
}

output "keycloak_public_url" {
  value = local.keycloak_public_url
}

output "keycloak_internal_url" {
  value = local.keycloak_internal_url
}

output "realm" {
  value = local.realm_name
}

output "oidc_issuer" {
  value = "${local.keycloak_internal_url}/realms/${local.realm_name}"
}

output "oidc_issuer_public" {
  value = "${local.keycloak_public_url}/realms/${local.realm_name}"
}

output "java_app_url" {
  value = var.enable_ingress ? "http://java.${local.public_host}" : "kubectl -n apps port-forward svc/java-oidc 8081:80"
}

output "golang_app_url" {
  value = var.enable_ingress ? "http://go.${local.public_host}" : "kubectl -n apps port-forward svc/golang-oidc 8082:80"
}

output "oidc_clients" {
  value = {
    java                 = local.java_client_id
    golang               = local.golang_client_id
    public_web           = local.public_client_id
    client_credentials   = local.service_client_id
  }
}

output "oidc_client_secrets" {
  sensitive = true
  value = {
    java               = random_password.java_client.result
    golang             = random_password.golang_client.result
    client_credentials = random_password.service_client.result
  }
}

output "demo_users" {
  sensitive = true
  value = {
    usernames = ["developer", "adminuser"]
    password  = random_password.demo_user.result
  }
}

output "devbox_ssh" {
  sensitive = true
  value = {
    user     = "dev"
    password = random_password.devbox.result
    command  = "kubectl -n workspace port-forward svc/devbox 2222:22 && ssh -p 2222 dev@127.0.0.1"
  }
}

output "useful_commands" {
  value = <<-EOT
    az aks get-credentials -g ${azurerm_resource_group.this.name} -n ${azurerm_kubernetes_cluster.this.name}
    kubectl -n identity get pods
    kubectl -n apps get pods
    kubectl -n workspace get pods
    kubectl -n workspace port-forward svc/devbox 2222:22
    ssh -p 2222 dev@127.0.0.1
    terraform output -raw keycloak_admin_password
  EOT
}
