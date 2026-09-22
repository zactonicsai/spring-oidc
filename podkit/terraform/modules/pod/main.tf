# Cloud-agnostic workload: ServiceAccount, (env Secret), (files ConfigMap), Deployment,
# (Service), (NetworkPolicy), (HPA). Mirrors podgen/k8s.py so both deploy paths agree.

terraform {
  required_version = ">= 1.3"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30, < 4.0"
    }
  }
}

locals {
  selector = { "app.kubernetes.io/name" = var.name }
  labels   = merge({ "app.kubernetes.io/name" = var.name, "app.kubernetes.io/managed-by" = "podkit" }, var.labels)

  # ConfigMap keys cannot contain "/": /app/config/x.properties -> app__config__x.properties
  file_keys = { for path, _ in var.files : path => replace(trimprefix(path, "/"), "/", "__") }

  has_secret_env = length(nonsensitive(var.secret_env)) > 0
  env_secret     = "${var.name}-env"
  files_cm       = "${var.name}-files"
  probe_enabled  = var.probe.type != "none"
  probe_port     = coalesce(var.probe.port, length(var.ports) > 0 ? var.ports[0].name : "80")

  # Pods restart automatically when files or secret values change.
  files_checksum  = substr(sha256(jsonencode(var.files)), 0, 16)
  secret_checksum = substr(nonsensitive(sha256(jsonencode(var.secret_env))), 0, 16)
}

resource "kubernetes_namespace_v1" "this" {
  count = var.create_namespace ? 1 : 0
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.labels
    annotations = merge(var.annotations, var.service_account_annotations)
  }
  automount_service_account_token = false
  depends_on                      = [kubernetes_namespace_v1.this]
}

resource "kubernetes_secret_v1" "env" {
  count = local.has_secret_env ? 1 : 0
  metadata {
    name      = local.env_secret
    namespace = var.namespace
    labels    = local.labels
  }
  data       = var.secret_env
  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_config_map_v1" "files" {
  count = length(var.files) > 0 ? 1 : 0
  metadata {
    name      = local.files_cm
    namespace = var.namespace
    labels    = local.labels
  }
  data       = { for path, content in var.files : local.file_keys[path] => content }
  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.labels
    annotations = var.annotations
  }

  spec {
    # null hands the replica count to the HPA (the provider leaves it untouched).
    replicas               = var.autoscaling.enabled ? null : tostring(var.replicas)
    revision_history_limit = 2

    selector {
      match_labels = local.selector
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0"
      }
    }

    template {
      metadata {
        labels = merge(local.labels, var.pod_labels)
        annotations = merge(
          { "podkit.dev/files-checksum" = local.files_checksum },
          local.has_secret_env ? { "podkit.dev/secret-checksum" = local.secret_checksum } : {},
        )
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.this.metadata[0].name
        automount_service_account_token = false
        node_selector                   = var.node_selector

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key                = toleration.value.key
            operator           = toleration.value.operator
            value              = toleration.value.value
            effect             = toleration.value.effect
            toleration_seconds = toleration.value.toleration_seconds
          }
        }

        security_context {
          run_as_non_root = var.security.run_as_non_root
          run_as_user     = var.security.run_as_user == null ? null : tostring(var.security.run_as_user)
          run_as_group    = var.security.run_as_group == null ? null : tostring(var.security.run_as_group)
          fs_group        = var.security.fs_group == null ? null : tostring(var.security.fs_group)
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = var.name
          image             = var.image
          image_pull_policy = var.image_pull_policy
          command           = var.command
          args              = var.args

          dynamic "port" {
            for_each = var.ports
            content {
              name           = port.value.name
              container_port = port.value.container_port
              protocol       = port.value.protocol
            }
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env" {
            for_each = var.env_from_secrets
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = env.value.secret
                  key  = env.value.key
                }
              }
            }
          }

          dynamic "env_from" {
            for_each = local.has_secret_env ? [1] : []
            content {
              secret_ref {
                name = local.env_secret
              }
            }
          }

          resources {
            requests = var.resources.requests
            limits   = var.resources.limits
          }

          dynamic "liveness_probe" {
            for_each = local.probe_enabled ? [1] : []
            content {
              dynamic "http_get" {
                for_each = var.probe.type == "http" ? [1] : []
                content {
                  path = var.probe.path
                  port = local.probe_port
                }
              }
              dynamic "tcp_socket" {
                for_each = var.probe.type == "tcp" ? [1] : []
                content {
                  port = local.probe_port
                }
              }
              initial_delay_seconds = var.probe.initial_delay
              period_seconds        = var.probe.period
            }
          }

          dynamic "readiness_probe" {
            for_each = local.probe_enabled ? [1] : []
            content {
              dynamic "http_get" {
                for_each = var.probe.type == "http" ? [1] : []
                content {
                  path = var.probe.path
                  port = local.probe_port
                }
              }
              dynamic "tcp_socket" {
                for_each = var.probe.type == "tcp" ? [1] : []
                content {
                  port = local.probe_port
                }
              }
              initial_delay_seconds = var.probe.initial_delay
              period_seconds        = var.probe.period
            }
          }

          dynamic "volume_mount" {
            for_each = var.files
            content {
              name       = "files"
              mount_path = volume_mount.key
              sub_path   = local.file_keys[volume_mount.key]
              read_only  = true
            }
          }

          dynamic "volume_mount" {
            for_each = var.mounts
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.path
              read_only  = volume_mount.value.read_only
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = var.security.read_only_root_filesystem
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        dynamic "volume" {
          for_each = length(var.files) > 0 ? [1] : []
          content {
            name = "files"
            config_map {
              name         = local.files_cm
              default_mode = "0444"
            }
          }
        }

        dynamic "volume" {
          for_each = var.mounts
          content {
            name = volume.value.name
            dynamic "secret" {
              for_each = volume.value.secret != null ? [1] : []
              content {
                secret_name  = volume.value.secret
                default_mode = "0400"
              }
            }
            dynamic "config_map" {
              for_each = volume.value.config_map != null ? [1] : []
              content {
                name = volume.value.config_map
              }
            }
          }
        }
      }
    }
  }

  wait_for_rollout = var.wait_for_rollout

  timeouts {
    create = var.rollout_timeout
    update = var.rollout_timeout
  }

  depends_on = [kubernetes_secret_v1.env, kubernetes_config_map_v1.files]
}

resource "kubernetes_service_v1" "this" {
  count = var.service.enabled && length(var.ports) > 0 ? 1 : 0
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.labels
    annotations = var.annotations
  }
  spec {
    type     = var.service.type
    selector = local.selector
    dynamic "port" {
      for_each = var.ports
      content {
        name        = port.value.name
        port        = port.key == 0 && var.service.port != null ? var.service.port : port.value.container_port
        target_port = port.value.name
        protocol    = port.value.protocol
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_network_policy_v1" "this" {
  count = var.network_policy.enabled ? 1 : 0
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    pod_selector {
      match_labels = local.selector
    }
    policy_types = ["Ingress", "Egress"]

    dynamic "ingress" {
      for_each = var.network_policy.ingress_from
      content {
        from {
          pod_selector {
            match_labels = ingress.value
          }
        }
        dynamic "ports" {
          for_each = var.ports
          content {
            port     = tostring(ports.value.container_port)
            protocol = ports.value.protocol
          }
        }
      }
    }

    dynamic "egress" {
      for_each = var.network_policy.allow_dns ? [1] : []
      content {
        to {
          namespace_selector {
            match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
          }
        }
        ports {
          port     = "53"
          protocol = "UDP"
        }
        ports {
          port     = "53"
          protocol = "TCP"
        }
      }
    }

    dynamic "egress" {
      for_each = var.network_policy.egress_https_any ? [1] : []
      content {
        to {
          ip_block {
            cidr = "0.0.0.0/0"
          }
        }
        ports {
          port     = "443"
          protocol = "TCP"
        }
      }
    }

    dynamic "egress" {
      for_each = var.network_policy.egress
      content {
        to {
          ip_block {
            cidr = egress.value.cidr
          }
        }
        ports {
          port     = tostring(egress.value.port)
          protocol = egress.value.protocol
        }
      }
    }

    dynamic "egress" {
      for_each = var.network_policy.egress_to
      content {
        to {
          pod_selector {
            match_labels = egress.value
          }
        }
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  count = var.autoscaling.enabled ? 1 : 0
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    min_replicas = var.autoscaling.min_replicas
    max_replicas = var.autoscaling.max_replicas
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.this.metadata[0].name
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.autoscaling.target_cpu
        }
      }
    }
  }
}
