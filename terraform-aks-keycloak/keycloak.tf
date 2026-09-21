resource "kubernetes_secret_v1" "keycloak_admin" {
  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace_v1.identity.metadata[0].name
  }

  data = {
    KC_BOOTSTRAP_ADMIN_USERNAME = "admin"
    KC_BOOTSTRAP_ADMIN_PASSWORD = random_password.keycloak_admin.result
  }
}

resource "kubernetes_config_map_v1" "keycloak_realm" {
  metadata {
    name      = "keycloak-realm-import"
    namespace = kubernetes_namespace_v1.identity.metadata[0].name
  }

  data = {
    "demo-realm.json" = templatefile("${path.module}/k8s/demo-realm.json.tftpl", {
      realm                 = local.realm_name
      demo_user_password    = random_password.demo_user.result
      java_client_id        = local.java_client_id
      java_client_secret    = random_password.java_client.result
      golang_client_id      = local.golang_client_id
      golang_client_secret  = random_password.golang_client.result
      public_client_id      = local.public_client_id
      service_client_id     = local.service_client_id
      service_client_secret = random_password.service_client.result
      public_host           = local.public_host
    })
  }
}

resource "kubernetes_deployment_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.identity.metadata[0].name
    labels    = { app = "keycloak" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "keycloak" }
    }

    template {
      metadata {
        labels = { app = "keycloak" }
        annotations = {
          "checksum/realm" = sha256(kubernetes_config_map_v1.keycloak_realm.data["demo-realm.json"])
        }
      }

      spec {
        container {
          name  = "keycloak"
          image = var.keycloak_image
          args  = ["start-dev", "--import-realm", "--health-enabled=true", "--http-enabled=true"]

          port {
            name           = "http"
            container_port = 8080
          }

          port {
            name           = "health"
            container_port = 9000
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.keycloak_admin.metadata[0].name
            }
          }

          env {
            name  = "KC_DB"
            value = "postgres"
          }

          env {
            name  = "KC_DB_URL_HOST"
            value = kubernetes_service_v1.postgres.metadata[0].name
          }

          env {
            name  = "KC_DB_URL_DATABASE"
            value = "keycloak"
          }

          env {
            name  = "KC_DB_USERNAME"
            value = "keycloak"
          }

          env {
            name = "KC_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.postgres.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          env {
            name  = "KC_HOSTNAME_STRICT"
            value = "false"
          }

          env {
            name  = "KC_PROXY_HEADERS"
            value = "xforwarded"
          }

          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }

          env {
            name  = "KC_HEALTH_ENABLED"
            value = "true"
          }

          env {
            name  = "JAVA_OPTS_APPEND"
            value = "-Xms256m -Xmx768m"
          }

          volume_mount {
            name       = "realm-import"
            mount_path = "/opt/keycloak/data/import"
            read_only  = true
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 9000
            }
            initial_delay_seconds = 45
            period_seconds        = 15
            timeout_seconds       = 5
            failure_threshold     = 20
          }

          liveness_probe {
            http_get {
              path = "/health/live"
              port = 9000
            }
            initial_delay_seconds = 90
            period_seconds        = 30
            timeout_seconds       = 5
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "1536Mi"
            }
          }
        }

        volume {
          name = "realm-import"
          config_map {
            name = kubernetes_config_map_v1.keycloak_realm.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment_v1.postgres]
}

resource "kubernetes_service_v1" "keycloak" {
  metadata {
    name      = local.keycloak_service
    namespace = kubernetes_namespace_v1.identity.metadata[0].name
  }

  spec {
    selector = { app = "keycloak" }

    port {
      name        = "http"
      port        = local.keycloak_port
      target_port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "keycloak" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.identity.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-buffer-size" = "16k"
      "nginx.ingress.kubernetes.io/proxy-body-size"   = "8m"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = local.public_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.keycloak.metadata[0].name
              port {
                number = local.keycloak_port
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}
