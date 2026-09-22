# Inputs shared by all cloud modules plus the GCP-specific ones.

variable "cluster_name" {
  description = "Name of the existing GKE cluster."
  type        = string
}

variable "project" {
  type = string
}

variable "location" {
  description = "Region (regional cluster) or zone (zonal cluster)."
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
  description = "Create a Google service account bound to the Kubernetes ServiceAccount (GKE Workload Identity must be enabled on the cluster and node pool)."
  type        = bool
  default     = false
}

variable "extra_roles" {
  description = "Additional project-level roles for the service account, e.g. roles/storage.objectViewer."
  type        = list(string)
  default     = []
}

variable "spot" {
  description = "Return the node selector and toleration for GKE Spot VMs."
  type        = bool
  default     = false
}

variable "secrets" {
  description = "ENV_VAR => Secret Manager secret name. Read at apply time; the service account gets secretAccessor on each."
  type        = map(string)
  default     = {}
}
