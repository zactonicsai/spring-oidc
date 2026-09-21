# ---------------------------------------------------------------------------
# terraform/local-docker — the whole app on plain Docker, no Kubernetes.
#   * builds one image per service from apps/<svc>
#   * one bridge network; containers get the SAME DNS names as in Kubernetes
#     (python-demo-web, python-demo-api) so config like API_URL just works
#   * only "expose: public" ports are published on your laptop
#   * optional base Linux "host" container configured by setup/*.sh (and Ansible)
# ---------------------------------------------------------------------------
module "app" {
  source                 = "../modules/app-config"
  config_path            = var.config_path
  image_registry         = "" # always build locally here
  host_settings_override = { RUN_DEMO_CONTAINERS = var.mount_docker_socket ? "true" : "false" }
}

locals {
  name = module.app.name
  root = abspath("${path.module}/../..")
  # secrets: only hand each service the keys it declares in app.config.yaml
  service_secret_env = { for n, s in module.app.services : n => [
    for k in s.secret_keys : "${k}=${lookup(var.secrets, k, "")}"
  ] }
}

resource "docker_network" "app" {
  name = local.name
}

# --- images ------------------------------------------------------------------
resource "docker_image" "svc" {
  for_each = module.app.services
  name     = each.value.image

  build {
    context    = "${local.root}/${each.value.build_context}"
    dockerfile = each.value.dockerfile
    tag        = [each.value.image]
    platform   = "linux/amd64"
  }

  # rebuild when any file in the build context changes
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("${local.root}/${each.value.build_context}", "**") : filesha1("${local.root}/${each.value.build_context}/${f}")]))
  }
}

# --- containers ---------------------------------------------------------------
resource "docker_container" "svc" {
  for_each = module.app.services
  name     = each.value.k8s_name # python-demo-web, python-demo-api
  image    = docker_image.svc[each.key].image_id
  restart  = "unless-stopped"

  env = concat(
    ["APP_NAME=${local.name}", "SERVICE_NAME=${each.key}", "APP_VERSION=${module.app.version}"],
    [for k, v in each.value.config : "${k}=${v}"],
    local.service_secret_env[each.key],
  )

  networks_advanced {
    name    = docker_network.app.name
    aliases = [each.value.k8s_name]
  }

  # publish only public ports (like a Kubernetes Service of type LoadBalancer would)
  dynamic "ports" {
    for_each = [for p in each.value.ports : p if p.expose == "public"]
    content {
      internal = ports.value.container_port
      external = ports.value.service_port
      protocol = lower(ports.value.protocol)
    }
  }

  # same hardening as the Pod securityContext
  user      = "65532:65532"
  read_only = true
  tmpfs     = { "/tmp" = "rw,noexec,nosuid,size=64m" }
  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  healthcheck {
    test     = ["CMD-SHELL", "python3 -c \"import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:${each.value.ports[0].container_port}${each.value.health.path}',timeout=2).status==200 else 1)\""]
    interval = "10s"
    timeout  = "3s"
    retries  = 3
  }
}
