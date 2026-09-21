variable "config_path" {
  type    = string
  default = "../../app.config.yaml"
}

variable "docker_host" {
  type    = string
  default = "unix:///var/run/docker.sock"
}

variable "node_image" {
  description = "kind node image (null = the default bundled with the provider's kind version). Pin like kindest/node:v1.34.0@sha256:... for reproducibility."
  type        = string
  default     = null
}

variable "secrets" {
  description = "Secret values by KEY, e.g. { API_TOKEN = \"...\" } (TF_VAR_secrets='{\"API_TOKEN\":\"x\"}')"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "install_metrics_server" {
  description = "Install metrics-server so the HorizontalPodAutoscaler has CPU numbers (kind does not ship it)."
  type        = bool
  default     = true
}
