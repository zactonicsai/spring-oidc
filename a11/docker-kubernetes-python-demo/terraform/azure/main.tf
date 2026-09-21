# ---------------------------------------------------------------------------
# terraform/azure — ACR + AKS (+ Key Vault, + base Linux VM) from app.config.yaml
# ---------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = local.location
  tags     = local.tags
}

# --- Container registry: the warehouse for images ----------------------------------
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name # letters + digits only, globally unique
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false # identities pull images; no shared password
  tags                = local.tags
}

# Build + push every service image with ACR Tasks (cloud build, no local Docker).
resource "terraform_data" "acr_build" {
  for_each = var.build_images ? module.cfg.services : {}
  triggers_replace = [
    azurerm_container_registry.acr.id,
    each.value.image,
    sha1(join("", [for f in fileset("${local.root}/${each.value.build_context}", "**") : filesha1("${local.root}/${each.value.build_context}/${f}")])),
  ]
  provisioner "local-exec" {
    command = "az acr build --registry ${azurerm_container_registry.acr.name} --image ${each.value.repository}:${each.value.tag} --file ${local.root}/${each.value.build_context}/${each.value.dockerfile} --platform linux/amd64 ${local.root}/${each.value.build_context}"
  }
}
