variable "config_path" {
  description = "Path to app.config.yaml"
  type        = string
  default     = "../../app.config.yaml"
}

variable "docker_host" {
  description = "Docker daemon socket"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "secrets" {
  description = "Secret values by KEY (e.g. { API_TOKEN = \"...\" }). Put them in secrets.auto.tfvars (git-ignored) or TF_VAR_secrets."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "create_base_host" {
  description = "Also start a base Linux 'host' container (hosts.baseImage.docker) and run setup/setup.sh + configure.sh in it — the local stand-in for the Azure VM."
  type        = bool
  default     = true
}

variable "mount_docker_socket" {
  description = "Mount the Docker socket into the base host container so configure.sh can start containers itself (docker-outside-of-docker). Off by default."
  type        = bool
  default     = false
}

variable "run_ansible" {
  description = "After the base host is up, run ansible/site.yml against it through the docker connection plugin (needs ansible-playbook locally)."
  type        = bool
  default     = false
}
