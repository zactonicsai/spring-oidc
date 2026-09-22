# Inputs shared by all cloud modules plus the Azure-specific ones.

variable "cluster_name" {
  description = "Name of the existing AKS cluster."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the AKS cluster (the managed identity is created here too)."
  type        = string
}

variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "service_account_name" {
  type = string
}

variable "create_identity" {
  description = "Create a user-assigned managed identity federated with the ServiceAccount (Azure Workload Identity; the cluster needs the OIDC issuer and the workload identity webhook enabled)."
  type        = bool
  default     = false
}

variable "key_vault_name" {
  description = "Key Vault that holds the secrets in `secrets`. Must use the RBAC permission model."
  type        = string
  default     = null
}

variable "key_vault_resource_group_name" {
  description = "Resource group of the Key Vault (defaults to resource_group_name)."
  type        = string
  default     = null
}

variable "extra_role_assignments" {
  description = "Additional role assignments for the identity: [{scope, role}]."
  type = list(object({
    scope = string
    role  = string
  }))
  default = []
}

variable "spot" {
  description = "Return the node selector and toleration for an AKS Spot node pool."
  type        = bool
  default     = false
}

variable "secrets" {
  description = "ENV_VAR => Key Vault secret name. Read at apply time; the identity gets Key Vault Secrets User on the vault."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
