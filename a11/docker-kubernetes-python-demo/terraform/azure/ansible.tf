# Inventory for ansible/site.yml pointing at the VM (written even if you don't run Ansible from Terraform).
resource "local_file" "ansible_inventory" {
  count    = local.create_vm ? 1 : 0
  filename = "${local.root}/ansible/inventory/azure.ini"
  content  = <<-EOT
    [app_hosts]
    ${local.vm_name} ansible_host=${azurerm_public_ip.vm[0].ip_address} ansible_user=${module.cfg.hosts.admin_user} ansible_ssh_private_key_file=${pathexpand(var.ssh_private_key_path)} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
    [app_hosts:vars]
    image_registry=${azurerm_container_registry.acr.login_server}
  EOT
}

# Optional: wait for cloud-init, then run the playbook (needs ansible-playbook + ssh locally).
resource "terraform_data" "ansible" {
  count            = local.create_vm && var.run_ansible ? 1 : 0
  triggers_replace = [azurerm_linux_virtual_machine.vm[0].id, filesha1("${local.root}/ansible/site.yml")]

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.vm[0].ip_address
    user        = module.cfg.hosts.admin_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }
  provisioner "remote-exec" {
    inline = ["cloud-init status --wait || true"]
  }
  provisioner "local-exec" {
    working_dir = "${local.root}/ansible"
    command     = "ansible-playbook -i inventory/azure.ini site.yml -e image_registry=${azurerm_container_registry.acr.login_server}"
  }
  depends_on = [local_file.ansible_inventory, azurerm_role_assignment.vm_acr_pull]
}
