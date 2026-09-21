# ---------------------------------------------------------------------------
# terraform/local-kind — a kind cluster + the Helm chart, all from app.config.yaml.
# Same result as scripts/01..04, expressed as Terraform resources.
# ---------------------------------------------------------------------------
module "app" {
  source         = "../modules/app-config"
  config_path    = var.config_path
  image_registry = ""
}

locals {
  name = module.app.name
  root = abspath("${path.module}/../..")
  # secrets.<service>.<KEY> — only the keys each service declares
  secrets_by_service = { for n, s in module.app.services : n => {
    for k in s.secret_keys : k => lookup(var.secrets, k, "")
  } if length(s.secret_keys) > 0 }
}

# --- 1. cluster ------------------------------------------------------------------
resource "kind_cluster" "this" {
  name           = module.app.local_cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    node {
      role = "control-plane"
    }
    node {
      role = "worker"
    }
  }
}

# --- 2. images: build locally, then copy into the kind nodes ------------------------
resource "docker_image" "svc" {
  for_each = module.app.services
  name     = each.value.image
  build {
    context    = "${local.root}/${each.value.build_context}"
    dockerfile = each.value.dockerfile
    tag        = [each.value.image]
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("${local.root}/${each.value.build_context}", "**") : filesha1("${local.root}/${each.value.build_context}/${f}")]))
  }
}

resource "terraform_data" "kind_load" {
  for_each         = module.app.services
  triggers_replace = [docker_image.svc[each.key].image_id, kind_cluster.this.id]
  provisioner "local-exec" {
    command = "kind load docker-image ${each.value.image} --name ${kind_cluster.this.name}"
  }
}

# --- 3. metrics-server (the autoscaler's thermometer) ---------------------------------
resource "helm_release" "metrics_server" {
  count      = var.install_metrics_server ? 1 : 0
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  wait       = true
  # kind kubelets use self-signed certificates
  set = [
    { name = "args[0]", value = "--kubelet-insecure-tls" },
  ]
  depends_on = [kind_cluster.this]
}

# --- 4. the app ----------------------------------------------------------------------
resource "helm_release" "app" {
  name             = local.name
  namespace        = module.app.namespace
  create_namespace = true
  chart            = "${local.root}/helm/python-demo"
  wait             = true
  timeout          = 300
  values = [
    yamlencode(merge(module.app.helm_values, {
      publicServiceType = "ClusterIP" # use kubectl port-forward locally
      secrets           = local.secrets_by_service
    }))
  ]
  depends_on = [terraform_data.kind_load, helm_release.metrics_server]
}
