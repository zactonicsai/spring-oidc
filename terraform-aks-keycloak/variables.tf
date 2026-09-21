variable "name_prefix" {
  description = "Short prefix used in Azure and Kubernetes resource names."
  type        = string
  default     = "kcaks"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus2"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Leave empty to use the latest supported default."
  type        = string
  default     = null
}

variable "node_count" {
  description = "System node pool size."
  type        = number
  default     = 3
}

variable "node_vm_size" {
  description = "VM size for the AKS system node pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "enable_ingress" {
  description = "Install ingress-nginx and expose Keycloak/apps via a public LoadBalancer."
  type        = bool
  default     = true
}

variable "ingress_host" {
  description = "Optional DNS name for ingress (e.g. idp.example.com). If empty, nip.io is used with the LB IP."
  type        = string
  default     = ""
}

variable "keycloak_image" {
  description = "Official Keycloak image."
  type        = string
  default     = "quay.io/keycloak/keycloak:26.7.4"
}

variable "postgres_image" {
  description = "Official PostgreSQL image used as Keycloak's database."
  type        = string
  default     = "postgres:16-alpine"
}

variable "java_runtime_image" {
  description = "Image used to run the Java OIDC example. Amazon Corretto 27 tracks JDK 27 GA."
  type        = string
  default     = "amazoncorretto:27"
}

variable "golang_runtime_image" {
  description = "Image used to run the Go OIDC example."
  type        = string
  default     = "golang:1.25"
}

variable "devbox_image" {
  description = "Developer workstation image. Build apps/devbox and push to ACR, or leave default to use the bundled public image plus install script."
  type        = string
  default     = "ubuntu:24.04"
}

variable "devbox_ssh_authorized_keys" {
  description = "OpenSSH public keys allowed to log into the developer pod as user 'dev'. Strongly preferred over password auth."
  type        = list(string)
  default     = []
}

variable "devbox_service_type" {
  description = "How to expose the developer SSH port. ClusterIP + kubectl port-forward is the safer default."
  type        = string
  default     = "ClusterIP"
  validation {
    condition     = contains(["ClusterIP", "LoadBalancer", "NodePort"], var.devbox_service_type)
    error_message = "devbox_service_type must be ClusterIP, LoadBalancer, or NodePort."
  }
}

variable "tags" {
  description = "Tags applied to Azure resources."
  type        = map(string)
  default = {
    project    = "aks-keycloak-oidc"
    managed-by = "terraform"
  }
}
