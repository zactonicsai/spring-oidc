variable "config_path" {
  type    = string
  default = "../../app.config.yaml"
}

variable "subscription_id" {
  description = "Azure subscription id (or set ARM_SUBSCRIPTION_ID)."
  type        = string
  default     = null
}

variable "location" {
  description = "Override targets.azure.location from app.config.yaml"
  type        = string
  default     = null
}

variable "name_suffix" {
  description = "Suffix for globally-unique names (ACR, Key Vault). null = random 6 chars kept in state."
  type        = string
  default     = null
}

variable "secrets" {
  description = "Secret values by KEY: { API_TOKEN = \"...\" }. Stored in Key Vault and injected into the chart. Use TF_VAR_secrets or secrets.auto.tfvars (git-ignored)."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Only used by the optional remote-exec wait / Ansible run."
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "build_images" {
  description = "Run `az acr build` for every service (needs az CLI logged in). Set false if CI pushes images."
  type        = bool
  default     = true
}

variable "deploy_helm" {
  description = "Deploy the Helm chart to AKS from this root."
  type        = bool
  default     = true
}

variable "create_vm" {
  description = "Override targets.azure.vm.enabled"
  type        = bool
  default     = null
}

variable "create_keyvault" {
  description = "Override targets.azure.keyVault.enabled"
  type        = bool
  default     = null
}

variable "run_ansible" {
  description = "After the VM boots, run ansible/site.yml against it over SSH."
  type        = bool
  default     = false
}

variable "public_service_source_ranges" {
  description = "Restrict the public LoadBalancer to these CIDRs, e.g. [\"203.0.113.4/32\"]. Empty = open."
  type        = list(string)
  default     = []
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
