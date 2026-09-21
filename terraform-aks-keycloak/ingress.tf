resource "helm_release" "ingress_nginx" {
  count = var.enable_ingress ? 1 : 0

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.12.3"
  namespace        = local.namespaces.ingress
  create_namespace = true
  wait             = true
  timeout          = 600

  set {
    name  = "controller.replicaCount"
    value = "1"
  }

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }

  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "true"
  }

  depends_on = [azurerm_kubernetes_cluster.this]
}

resource "time_sleep" "wait_for_ingress_ip" {
  count           = var.enable_ingress ? 1 : 0
  create_duration = "90s"
  depends_on      = [helm_release.ingress_nginx]
}

data "kubernetes_service_v1" "ingress_nginx" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = "ingress-nginx-controller"
    namespace = local.namespaces.ingress
  }

  depends_on = [time_sleep.wait_for_ingress_ip]
}

locals {
  ingress_ip = var.enable_ingress ? try(
    data.kubernetes_service_v1.ingress_nginx[0].status[0].load_balancer[0].ingress[0].ip,
    ""
  ) : ""

  public_host = var.ingress_host != "" ? var.ingress_host : (
    local.ingress_ip != "" ? "${local.ingress_ip}.nip.io" : "keycloak.local"
  )

  keycloak_public_url = var.enable_ingress ? "http://${local.public_host}" : local.keycloak_internal_url
}
