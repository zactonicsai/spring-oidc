# The command pod: a small long-running pod (sleep infinity) with kubectl, Ansible, openssl,
# keytool and psql. Configuration steps run inside it, so the tools and the network path to the
# cluster live in the cluster and not on laptops or CI runners. Scale to 0 when idle.

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
  labels = { "app.kubernetes.io/name" = var.name, "app.kubernetes.io/managed-by" = "podkit" }
  rules = [
    { api_groups = [""], resources = ["pods"], verbs = ["get", "list", "watch"] },
    { api_groups = [""], resources = ["pods/exec"], verbs = ["create"] },
    { api_groups = [""], resources = ["pods/log"], verbs = ["get"] },
    { api_groups = [""], resources = ["secrets", "configmaps"], verbs = ["get", "list", "create", "update", "patch", "delete"] },
    { api_groups = [""], resources = ["services"], verbs = ["get", "list"] },
    { api_groups = ["apps"], resources = ["deployments"], verbs = ["get", "list", "patch"] },
  ]
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
}

# Least privilege: namespaced Roles only, one per target namespace. No cluster-wide access.
resource "kubernetes_role_v1" "target" {
  for_each = toset(var.target_namespaces)
  metadata {
    name      = "${var.name}-configure"
    namespace = each.value
    labels    = local.labels
  }
  dynamic "rule" {
    for_each = local.rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = rule.value.verbs
    }
  }
}

resource "kubernetes_role_binding_v1" "target" {
  for_each = toset(var.target_namespaces)
  metadata {
    name      = "${var.name}-configure"
    namespace = each.value
    labels    = local.labels
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.target[each.key].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.this.metadata[0].name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
  spec {
    replicas               = tostring(var.replicas)
    revision_history_limit = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = var.name }
    }
    strategy {
      type = "Recreate"
    }
    template {
      metadata {
        labels = local.labels
      }
      spec {
        service_account_name            = kubernetes_service_account_v1.this.metadata[0].name
        automount_service_account_token = true
        node_selector                   = var.node_selector

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        security_context {
          run_as_non_root = true
          run_as_user     = "1000"
          run_as_group    = "1000"
          fs_group        = "1000"
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = var.name
          image             = var.image
          image_pull_policy = var.image_pull_policy
          command           = ["sleep", "infinity"]
          working_dir       = "/work"

          resources {
            requests = var.resources.requests
            limits   = var.resources.limits
          }

          volume_mount {
            name       = "work"
            mount_path = "/work"
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "work"
          empty_dir {}
        }
      }
    }
  }
  wait_for_rollout = var.replicas > 0
}
