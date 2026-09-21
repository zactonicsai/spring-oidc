variable "config_path" {
  description = "Path to app.config.yaml (the single source of truth)."
  type        = string
}

variable "image_registry" {
  description = "Override sources.imageRegistry (e.g. the ACR login server). null = use the file."
  type        = string
  default     = null
}

variable "host_settings_override" {
  description = "Override individual hosts.settings keys (e.g. RUN_DEMO_CONTAINERS = \"false\")."
  type        = map(string)
  default     = {}
}
