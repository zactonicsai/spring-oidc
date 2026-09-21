module "app" {
  source      = "../modules/app-config"
  config_path = var.config_path
  # images live in ACR: <acr>.azurecr.io/<app>-<svc>:<tag>
  image_registry = azurerm_container_registry.acr.login_server
}

# A second, registry-free view is needed BEFORE the ACR exists (names, locations, VM settings).
module "cfg" {
  source         = "../modules/app-config"
  config_path    = var.config_path
  image_registry = ""
}

locals {
  name     = module.cfg.name
  az       = module.cfg.azure
  location = coalesce(var.location, local.az.location)
  suffix   = coalesce(var.name_suffix, random_string.suffix.result)
  root     = abspath("${path.module}/../..")

  rg_name       = local.az.resource_group
  acr_name      = coalesce(local.az.acr_name, "${replace(local.name, "-", "")}acr${local.suffix}")
  aks_name      = "aks-${local.name}"
  kv_name       = substr("kv-${local.name}-${local.suffix}", 0, 24)
  vm_name       = "vm-${local.name}"
  create_vm     = coalesce(var.create_vm, local.az.vm_enabled)
  create_kv     = coalesce(var.create_keyvault, local.az.keyvault_enabled)
  aks_net       = local.az.aks_net_policy
  k8s_version   = local.az.aks_version != "" ? local.az.aks_version : null
  ssh_pub       = file(pathexpand(var.ssh_public_key_path))
  service_names = module.cfg.service_names

  tags = merge({
    project      = local.name
    owner        = module.cfg.owner
    "managed-by" = "terraform"
  }, module.cfg.labels, var.extra_tags)

  # secrets.<service>.<KEY> for the chart — only keys a service declares
  secrets_by_service = { for n, s in module.cfg.services : n => {
    for k in s.secret_keys : k => lookup(var.secrets, k, "")
  } if length(s.secret_keys) > 0 }
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}
