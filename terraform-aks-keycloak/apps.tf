resource "kubernetes_config_map_v1" "java_src" {
  metadata {
    name      = "java-oidc-src"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  data = {
    "App.java" = file("${path.module}/apps/java-oidc/App.java")
  }
}

resource "kubernetes_config_map_v1" "golang_src" {
  metadata {
    name      = "golang-oidc-src"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  data = {
    "main.go" = file("${path.module}/apps/golang-oidc/main.go")
  }
}

resource "kubernetes_secret_v1" "oidc_clients" {
  metadata {
    name      = "oidc-clients"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  data = {
    JAVA_CLIENT_SECRET   = random_password.java_client.result
    GOLANG_CLIENT_SECRET = random_password.golang_client.result
    SERVICE_CLIENT_SECRET = random_password.service_client.result
  }
}

resource "kubernetes_deployment_v1" "java_oidc" {
  metadata {
    name      = "java-oidc"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
    labels    = { app = "java-oidc" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "java-oidc" }
    }
    template {
      metadata {
        labels = { app = "java-oidc" }
      }
      spec {
        container {
          name    = "java-oidc"
          image   = var.java_runtime_image
          command = ["java"]
          args    = ["/src/App.java"]

          port {
            container_port = local.java_app_port
          }

          env {
            name  = "PORT"
            value = tostring(local.java_app_port)
          }
          env {
            name  = "OIDC_ISSUER"
            value = "${local.keycloak_internal_url}/realms/${local.realm_name}"
          }
          env {
            name  = "OIDC_CLIENT_ID"
            value = local.java_client_id
          }
          env {
            name = "OIDC_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.oidc_clients.metadata[0].name
                key  = "JAVA_CLIENT_SECRET"
              }
            }
          }

          volume_mount {
            name       = "src"
            mount_path = "/src"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = local.java_app_port
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "768Mi"
            }
          }
        }

        volume {
          name = "src"
          config_map {
            name = kubernetes_config_map_v1.java_src.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "java_oidc" {
  metadata {
    name      = "java-oidc"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }
  spec {
    selector = { app = "java-oidc" }
    port {
      port        = 80
      target_port = local.java_app_port
    }
  }
}

resource "kubernetes_deployment_v1" "golang_oidc" {
  metadata {
    name      = "golang-oidc"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
    labels    = { app = "golang-oidc" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "golang-oidc" }
    }
    template {
      metadata {
        labels = { app = "golang-oidc" }
      }
      spec {
        container {
          name    = "golang-oidc"
          image   = var.golang_runtime_image
          command = ["go", "run", "/src/main.go"]

          port {
            container_port = local.golang_app_port
          }

          env {
            name  = "GO111MODULE"
            value = "off"
          }
          env {
            name  = "PORT"
            value = tostring(local.golang_app_port)
          }
          env {
            name  = "OIDC_ISSUER"
            value = "${local.keycloak_internal_url}/realms/${local.realm_name}"
          }
          env {
            name  = "OIDC_CLIENT_ID"
            value = local.golang_client_id
          }
          env {
            name = "OIDC_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.oidc_clients.metadata[0].name
                key  = "GOLANG_CLIENT_SECRET"
              }
            }
          }

          volume_mount {
            name       = "src"
            mount_path = "/src"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = local.golang_app_port
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "src"
          config_map {
            name = kubernetes_config_map_v1.golang_src.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "golang_oidc" {
  metadata {
    name      = "golang-oidc"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }
  spec {
    selector = { app = "golang-oidc" }
    port {
      port        = 80
      target_port = local.golang_app_port
    }
  }
}

resource "kubernetes_ingress_v1" "apps" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = "oidc-apps"
    namespace = kubernetes_namespace_v1.apps.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "java.${local.public_host}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.java_oidc.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "go.${local.public_host}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.golang_oidc.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}
