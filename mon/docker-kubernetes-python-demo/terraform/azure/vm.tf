# ---------------------------------------------------------------------------
# Base Linux VM configured from app.config.yaml (the "no Kubernetes" path):
#   * image      : hosts.baseImage.azure
#   * NSG rules  : hosts.exposePorts (one inbound rule each)
#   * cloud-init : embeds host-config.env, host-files.tsv, env/*.env, setup.sh, configure.sh
#   * identity   : system-assigned + AcrPull -> configure.sh pulls images without a password
# ---------------------------------------------------------------------------
locals {
  cloud_init = join("\n", ["#cloud-config", yamlencode({
    package_update = true
    packages       = module.cfg.hosts.packages
    write_files = concat([
      { path = "/opt/${local.name}/host-config.env", permissions = "0640", encoding = "b64", content = base64encode(module.app.host_config_env) },
      { path = "/opt/${local.name}/host-files.tsv", permissions = "0640", encoding = "b64", content = base64encode(module.app.host_files_tsv) },
      { path = "/opt/${local.name}/setup.sh", permissions = "0750", encoding = "b64", content = base64encode(file("${local.root}/${module.cfg.hosts.setup_script}")) },
      { path = "/opt/${local.name}/configure.sh", permissions = "0750", encoding = "b64", content = base64encode(file("${local.root}/${module.cfg.hosts.configure_script}")) },
      ], [
      for svc, text in module.app.host_service_envs :
      { path = "/opt/${local.name}/env/${svc}.env", permissions = "0640", encoding = "b64", content = base64encode(text) }
    ])
    runcmd = [
      "bash /opt/${local.name}/setup.sh 2>&1 | tee -a /var/log/${local.name}-setup.log",
      "bash /opt/${local.name}/configure.sh 2>&1 | tee -a /var/log/${local.name}-configure.log",
    ]
    final_message = "${local.name} host setup finished after $UPTIME seconds"
  })])
}

resource "azurerm_virtual_network" "vnet" {
  count               = local.create_vm ? 1 : 0
  name                = "vnet-${local.name}"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_subnet" "vm" {
  count                = local.create_vm ? 1 : 0
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.10.1.0/24"]
}

# Network Security Group = the cloud firewall in front of the VM. Rules come from hosts.exposePorts.
resource "azurerm_network_security_group" "vm" {
  count               = local.create_vm ? 1 : 0
  name                = "nsg-${local.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  dynamic "security_rule" {
    for_each = { for i, p in module.cfg.hosts.expose_ports : p.name => merge(p, { priority = 1000 + i * 10 }) }
    content {
      name                       = "allow-${security_rule.key}"
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = title(lower(security_rule.value.protocol)) # Tcp / Udp
      source_port_range          = "*"
      destination_port_range     = tostring(security_rule.value.port)
      source_address_prefix      = security_rule.value.source # "*" or a CIDR like 203.0.113.4/32
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_public_ip" "vm" {
  count               = local.create_vm ? 1 : 0
  name                = "pip-${local.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "vm" {
  count               = local.create_vm ? 1 : 0
  name                = "nic-${local.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  count                     = local.create_vm ? 1 : 0
  network_interface_id      = azurerm_network_interface.vm[0].id
  network_security_group_id = azurerm_network_security_group.vm[0].id
}

resource "azurerm_linux_virtual_machine" "vm" {
  count                 = local.create_vm ? 1 : 0
  name                  = local.vm_name
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = local.az.vm_size
  admin_username        = module.cfg.hosts.admin_user
  network_interface_ids = [azurerm_network_interface.vm[0].id]
  custom_data           = base64encode(local.cloud_init)
  tags                  = local.tags

  admin_ssh_key {
    username   = module.cfg.hosts.admin_user
    public_key = local.ssh_pub
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = module.cfg.hosts.azure_base_image.publisher
    offer     = module.cfg.hosts.azure_base_image.offer
    sku       = module.cfg.hosts.azure_base_image.sku
    version   = module.cfg.hosts.azure_base_image.version
  }
  identity {
    type = "SystemAssigned"
  }
}

# The VM identity may pull images from ACR (configure.sh exchanges its IMDS token for an ACR token)
resource "azurerm_role_assignment" "vm_acr_pull" {
  count                            = local.create_vm ? 1 : 0
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_linux_virtual_machine.vm[0].identity[0].principal_id
  skip_service_principal_aad_check = true
}
