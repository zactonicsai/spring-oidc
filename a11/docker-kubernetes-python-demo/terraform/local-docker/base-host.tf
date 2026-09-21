# ---------------------------------------------------------------------------
# Base Linux "host" container: the local stand-in for the Azure VM.
# Terraform writes the same files cloud-init would (host-config.env, host-files.tsv,
# env/*.env) into generated/, mounts them with setup/ at /opt/<app>, then runs
# setup.sh + configure.sh inside — exactly the scripts the VM runs at first boot.
# ---------------------------------------------------------------------------
resource "local_file" "host_config" {
  count           = var.create_base_host ? 1 : 0
  filename        = "${path.module}/generated/host-config.env"
  content         = module.app.host_config_env
  file_permission = "0640"
}

resource "local_file" "host_files" {
  count           = var.create_base_host ? 1 : 0
  filename        = "${path.module}/generated/host-files.tsv"
  content         = module.app.host_files_tsv
  file_permission = "0640"
}

resource "local_file" "service_env" {
  for_each        = var.create_base_host ? module.app.host_service_envs : {}
  filename        = "${path.module}/generated/env/${each.key}.env"
  content         = each.value
  file_permission = "0640"
}

resource "docker_image" "base" {
  count = var.create_base_host ? 1 : 0
  name  = module.app.hosts.docker_base_image # e.g. ubuntu:24.04 from hosts.baseImage.docker
}

resource "docker_container" "base_host" {
  count   = var.create_base_host ? 1 : 0
  name    = "${local.name}-host"
  image   = docker_image.base[0].image_id
  command = ["sleep", "infinity"]
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.app.name
  }

  # the scripts + rendered config, read-only, at the same path cloud-init uses on the VM
  volumes {
    host_path      = "${local.root}/setup"
    container_path = "/opt/${local.name}/scripts"
    read_only      = true
  }
  volumes {
    host_path      = abspath("${path.module}/generated")
    container_path = "/opt/${local.name}/config"
    read_only      = true
  }
  dynamic "volumes" {
    for_each = var.mount_docker_socket ? [1] : []
    content {
      host_path      = "/var/run/docker.sock"
      container_path = "/var/run/docker.sock"
    }
  }
  depends_on = [local_file.host_config, local_file.host_files, local_file.service_env]
}

# Run setup.sh then configure.sh inside the base host (re-runs when config or scripts change).
resource "terraform_data" "configure_base_host" {
  count = var.create_base_host ? 1 : 0
  triggers_replace = [
    module.app.host_config_env,
    module.app.host_files_tsv,
    filesha1("${local.root}/setup/setup.sh"),
    filesha1("${local.root}/setup/configure.sh"),
    docker_container.base_host[0].id,
  ]
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      c=${docker_container.base_host[0].name}
      docker exec $c bash -c 'mkdir -p /opt/${local.name}/env && cp /opt/${local.name}/config/host-config.env /opt/${local.name}/config/host-files.tsv /opt/${local.name}/ && cp /opt/${local.name}/config/env/*.env /opt/${local.name}/env/ && cp /opt/${local.name}/scripts/*.sh /opt/${local.name}/'
      docker exec $c bash /opt/${local.name}/setup.sh
      docker exec $c bash /opt/${local.name}/configure.sh
    EOT
  }
}

# Optional: configure the same container with Ansible through the docker connection plugin.
resource "local_file" "ansible_inventory" {
  count    = var.create_base_host ? 1 : 0
  filename = "${local.root}/ansible/inventory/local-docker.ini"
  content  = <<-EOT
    [app_hosts]
    ${local.name}-host ansible_connection=community.docker.docker ansible_python_interpreter=/usr/bin/python3
  EOT
}

resource "terraform_data" "ansible" {
  count            = var.create_base_host && var.run_ansible ? 1 : 0
  triggers_replace = [terraform_data.configure_base_host[0].id, filesha1("${local.root}/ansible/site.yml")]
  provisioner "local-exec" {
    working_dir = "${local.root}/ansible"
    command     = "ansible-playbook -i inventory/local-docker.ini site.yml -e run_demo_containers=false"
  }
  depends_on = [local_file.ansible_inventory]
}
