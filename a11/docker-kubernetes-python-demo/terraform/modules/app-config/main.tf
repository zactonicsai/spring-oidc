# ---------------------------------------------------------------------------
# module "app-config": parse app.config.yaml once, expose a normalised model
# that terraform/local-docker, terraform/local-kind and terraform/azure share.
# The ${name} ${version} ${registry} placeholders are expanded here.
# ---------------------------------------------------------------------------
locals {
  raw      = yamldecode(file(var.config_path))
  name     = local.raw.metadata.name
  version  = tostring(local.raw.metadata.version)
  registry = var.image_registry != null ? var.image_registry : try(local.raw.sources.imageRegistry, "")
  ns       = coalesce(try(local.raw.kubernetes.namespace, ""), local.name)

  # placeholder expansion table (HCL has no user functions, so we inline replace())
  ph = { "$${name}" = local.name, "$${version}" = local.version, "$${registry}" = local.registry }

  services = [for s in local.raw.services : {
    name          = s.name
    k8s_name      = "${local.name}-${s.name}"
    build_context = try(s.build.context, "")
    dockerfile    = try(s.build.dockerfile, "Dockerfile")
    repository    = replace(replace(replace(s.image.repository, "$${name}", local.name), "$${version}", local.version), "$${registry}", local.registry)
    tag           = coalesce(try(tostring(s.image.tag), ""), local.version)
    pull_policy   = try(s.image.pullPolicy, "IfNotPresent")
    ports = [for p in s.ports : {
      name           = p.name
      container_port = p.containerPort
      service_port   = try(p.servicePort, p.containerPort)
      protocol       = try(p.protocol, "TCP")
      expose         = try(p.expose, "cluster")
    }]
    config      = { for k, v in try(s.config, {}) : k => replace(replace(replace(tostring(v), "$${name}", local.name), "$${version}", local.version), "$${registry}", local.registry) }
    secret_keys = [for x in try(s.secrets, []) : x.name]
    health = {
      path                         = try(s.health.path, "/health")
      readinessInitialDelaySeconds = try(s.health.readinessInitialDelaySeconds, 2)
      livenessInitialDelaySeconds  = try(s.health.livenessInitialDelaySeconds, 5)
    }
    replicas = try(s.scale.replicas, 1)
    autoscale = {
      enabled                        = try(s.scale.autoscale.enabled, false)
      minReplicas                    = try(s.scale.autoscale.minReplicas, 1)
      maxReplicas                    = try(s.scale.autoscale.maxReplicas, 1)
      targetCPUUtilizationPercentage = try(s.scale.autoscale.targetCPUUtilizationPercentage, 70)
    }
    resources  = try(s.resources, {})
    allow_from = try(s.network.allowFrom, [])
    is_public  = length([for p in s.ports : p if try(p.expose, "cluster") == "public"]) > 0
  }]

  services_by_name = { for s in local.services : s.name => merge(s, {
    image = "${local.registry != "" ? "${local.registry}/" : ""}${s.repository}:${s.tag}"
  }) }

  files = [for f in try(local.raw.sources.files, []) : {
    name   = f.name
    url    = f.url
    dest   = replace(f.dest, "$${name}", local.name)
    mode   = try(f.mode, "0644")
    owner  = try(f.owner, "root")
    sha256 = try(f.sha256, "")
  }]

  hosts = {
    docker_base_image = try(local.raw.hosts.baseImage.docker, "ubuntu:24.04")
    azure_base_image = {
      publisher = try(local.raw.hosts.baseImage.azure.publisher, "Canonical")
      offer     = try(local.raw.hosts.baseImage.azure.offer, "ubuntu-24_04-lts")
      sku       = try(local.raw.hosts.baseImage.azure.sku, "server")
      version   = try(local.raw.hosts.baseImage.azure.version, "latest")
    }
    admin_user = try(local.raw.hosts.adminUser, "azureuser")
    packages   = try(local.raw.hosts.packages, ["curl", "ca-certificates"])
    expose_ports = [for p in try(local.raw.hosts.exposePorts, []) : {
      name     = p.name
      port     = p.port
      protocol = try(p.protocol, "TCP")
      source   = try(p.source, "*")
    }]
    setup_script     = try(local.raw.hosts.setupScript, "setup/setup.sh")
    configure_script = try(local.raw.hosts.configureScript, "setup/configure.sh")
    ansible_enabled  = try(local.raw.hosts.ansible.enabled, false)
    ansible_playbook = try(local.raw.hosts.ansible.playbook, "ansible/site.yml")
    settings         = merge({ for k, v in try(local.raw.hosts.settings, {}) : k => tostring(v) }, var.host_settings_override)
  }

  azure = {
    location         = try(local.raw.targets.azure.location, "eastus")
    resource_group   = coalesce(try(local.raw.targets.azure.resourceGroup, ""), "rg-${local.name}")
    acr_name         = try(local.raw.targets.azure.acrName, "")
    aks_node_count   = try(local.raw.targets.azure.aks.nodeCount, 2)
    aks_vm_size      = try(local.raw.targets.azure.aks.nodeVmSize, "Standard_B2ms")
    aks_autoscale    = try(local.raw.targets.azure.aks.autoscale.enabled, false)
    aks_min_count    = try(local.raw.targets.azure.aks.autoscale.minCount, 1)
    aks_max_count    = try(local.raw.targets.azure.aks.autoscale.maxCount, 3)
    aks_tier         = try(local.raw.targets.azure.aks.tier, "free")
    aks_version      = try(local.raw.targets.azure.aks.kubernetesVersion, "")
    aks_net_policy   = try(local.raw.targets.azure.aks.networkPolicy, "cilium")
    vm_enabled       = try(local.raw.targets.azure.vm.enabled, false)
    vm_size          = try(local.raw.targets.azure.vm.size, "Standard_B1s")
    keyvault_enabled = try(local.raw.targets.azure.keyVault.enabled, false)
  }

  # ---- Helm values: identical shape to build/helm-values.yaml from tools/appconfig.py ----
  helm_values = {
    nameOverride = local.name
    namespace    = local.ns
    version      = local.version
    global = {
      imageRegistry   = local.registry
      imagePullSecret = try(local.raw.sources.imagePullSecret, "")
      labels          = { for k, v in try(local.raw.metadata.labels, {}) : k => tostring(v) }
    }
    networkPolicy = {
      enabled     = try(local.raw.kubernetes.networkPolicy.enabled, true)
      defaultDeny = try(local.raw.kubernetes.networkPolicy.defaultDeny, true)
    }
    ingress = {
      enabled   = try(local.raw.kubernetes.ingress.enabled, false)
      className = try(local.raw.kubernetes.ingress.className, "")
      host      = try(local.raw.kubernetes.ingress.host, "")
    }
    services = { for s in local.services : s.name => {
      image = { repository = s.repository, tag = s.tag, pullPolicy = s.pull_policy }
      ports = [for p in s.ports : {
        name = p.name, containerPort = p.container_port, servicePort = p.service_port, protocol = p.protocol, expose = p.expose
      }]
      config     = s.config
      secretKeys = s.secret_keys
      health     = s.health
      replicas   = s.replicas
      autoscale  = s.autoscale
      resources  = s.resources
      allowFrom  = s.allow_from
    } }
    secrets = {}
  }

  # ---- host-config.env / host-files.tsv: identical to tools/appconfig.py render host ----
  host_config_env = join("\n", concat(
    [
      "# GENERATED by terraform (module app-config) from app.config.yaml",
      "APP_NAME=${local.name}",
      "APP_VERSION=${local.version}",
      "IMAGE_REGISTRY='${local.registry}'",
      "ADMIN_USER=${local.hosts.admin_user}",
      "PACKAGES='${join(" ", local.hosts.packages)}'",
      "EXPOSE_PORTS='${join(" ", [for p in local.hosts.expose_ports : "${p.port}/${lower(p.protocol)}"])}'",
      "SERVICES='${join(" ", [for s in local.services : s.name])}'",
    ],
    flatten([for s in local.services : [
      "SERVICE_${upper(replace(s.name, "-", "_"))}_IMAGE=${local.services_by_name[s.name].image}",
      "SERVICE_${upper(replace(s.name, "-", "_"))}_HOST_PORT=${s.ports[0].service_port}",
      "SERVICE_${upper(replace(s.name, "-", "_"))}_CONTAINER_PORT=${s.ports[0].container_port}",
      "SERVICE_${upper(replace(s.name, "-", "_"))}_EXPOSE=${s.ports[0].expose}",
    ]]),
    [for k, v in local.hosts.settings : "SETTING_${k}='${v}'"],
    [""]
  ))

  # one docker --env-file per service: APP_NAME/SERVICE_NAME/APP_VERSION + services[].config
  host_service_envs = { for s in local.services : s.name => join("\n", concat(
    ["APP_NAME=${local.name}", "SERVICE_NAME=${s.name}", "APP_VERSION=${local.version}"],
    [for k, v in s.config : "${k}=${v}"], [""]
  )) }

  host_files_tsv = join("", [for f in local.files : "${f.name}\t${f.url}\t${f.dest}\t${f.mode}\t${f.sha256 != "" ? f.sha256 : "-"}\n"])
}
