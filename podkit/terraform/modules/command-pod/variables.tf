variable "namespace" {
  description = "Namespace of the command pod."
  type        = string
  default     = "ops"
}

variable "name" {
  type    = string
  default = "command-pod"
}

variable "image" {
  description = "Image built from command-pod/Dockerfile (kubectl, ansible, openssl, keytool, psql)."
  type        = string
}

variable "image_pull_policy" {
  type    = string
  default = "IfNotPresent"
}

variable "target_namespaces" {
  description = "Namespaces the command pod may configure (a namespaced Role + RoleBinding is created in each)."
  type        = list(string)
  default     = ["default"]
}

variable "replicas" {
  description = "1 while you deploy, 0 when idle (scale to zero costs nothing)."
  type        = number
  default     = 1
}

variable "resources" {
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

variable "node_selector" {
  type    = map(string)
  default = {}
}

variable "tolerations" {
  type = list(object({
    key      = optional(string)
    operator = optional(string, "Equal")
    value    = optional(string)
    effect   = optional(string)
  }))
  default = []
}
