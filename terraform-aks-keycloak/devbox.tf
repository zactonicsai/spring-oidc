resource "kubernetes_secret_v1" "devbox" {
  metadata {
    name      = "devbox-auth"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  data = {
    DEV_PASSWORD = random_password.devbox.result
  }
}

resource "kubernetes_config_map_v1" "devbox_bootstrap" {
  metadata {
    name      = "devbox-bootstrap"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  data = {
    "bootstrap.sh"     = file("${path.module}/apps/devbox/bootstrap.sh")
    "authorized_keys"  = join("\n", var.devbox_ssh_authorized_keys)
  }
}

resource "kubernetes_persistent_volume_claim_v1" "devbox_home" {
  metadata {
    name      = "devbox-home"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "managed-csi"
    resources {
      requests = {
        storage = "32Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "devbox" {
  metadata {
    name      = "devbox"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
    labels    = { app = "devbox" }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "devbox" }
    }

    template {
      metadata {
        labels = { app = "devbox" }
      }

      spec {
        hostname = "devbox"

        container {
          name              = "devbox"
          image             = var.devbox_image
          image_pull_policy = "IfNotPresent"
          command           = ["bash", "/opt/bootstrap/bootstrap.sh"]

          port {
            name           = "ssh"
            container_port = 22
          }

          env {
            name = "DEV_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.devbox.metadata[0].name
                key  = "DEV_PASSWORD"
              }
            }
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/dev"
          }

          volume_mount {
            name       = "bootstrap"
            mount_path = "/opt/bootstrap"
            read_only  = true
          }

          volume_mount {
            name       = "ssh-bootstrap"
            mount_path = "/etc/ssh-bootstrap"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }

          security_context {
            privileged = false
            capabilities {
              add = ["SYS_CHROOT", "AUDIT_WRITE"]
            }
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.devbox_home.metadata[0].name
          }
        }

        volume {
          name = "bootstrap"
          config_map {
            name         = kubernetes_config_map_v1.devbox_bootstrap.metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "ssh-bootstrap"
          config_map {
            name = kubernetes_config_map_v1.devbox_bootstrap.metadata[0].name
            items {
              key  = "authorized_keys"
              path = "authorized_keys"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "devbox" {
  metadata {
    name      = "devbox"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    type     = var.devbox_service_type
    selector = { app = "devbox" }

    port {
      name        = "ssh"
      port        = 22
      target_port = 22
    }
  }
}
