# Inputs shared by all cloud modules (cluster_name, name, namespace, service_account_name,
# create_identity, spot, secrets) plus the AWS-specific ones.

variable "cluster_name" {
  description = "Name of the existing EKS cluster."
  type        = string
}

variable "region" {
  type = string
}

variable "name" {
  description = "Workload name; used for the IAM role name."
  type        = string
}

variable "namespace" {
  type = string
}

variable "service_account_name" {
  type = string
}

variable "create_identity" {
  description = "Create an IAM role the pod can assume (IRSA or EKS Pod Identity)."
  type        = bool
  default     = false
}

variable "identity_mode" {
  description = "irsa (OIDC federation, needs the cluster's OIDC provider registered in IAM) or pod-identity (needs the eks-pod-identity-agent add-on)."
  type        = string
  default     = "irsa"
  validation {
    condition     = contains(["irsa", "pod-identity"], var.identity_mode)
    error_message = "identity_mode must be irsa or pod-identity."
  }
}

variable "extra_policy_arns" {
  description = "Additional managed policies attached to the pod's role."
  type        = list(string)
  default     = []
}

variable "spot" {
  description = "Return a node selector for Spot capacity (managed node groups label eks.amazonaws.com/capacityType=SPOT)."
  type        = bool
  default     = false
}

variable "secrets" {
  description = "ENV_VAR => Secrets Manager secret name or ARN. Read at apply time; the role is granted GetSecretValue on them."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
