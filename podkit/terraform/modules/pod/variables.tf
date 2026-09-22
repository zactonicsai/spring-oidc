# Inputs of the cloud-agnostic pod module. The generated root module (podgen) fills these from
# a PodConfig; the cloud module supplies secret values, identity annotations and spot hints.

variable "name" {
  description = "Workload name (Deployment, Service, ServiceAccount, ConfigMap and NetworkPolicy share it)."
  type        = string
}

variable "namespace" {
  type = string
}

variable "create_namespace" {
  description = "Create the namespace if it does not exist yet."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to every object; must contain app.kubernetes.io/name = name."
  type        = map(string)
  default     = {}
}

variable "annotations" {
  type    = map(string)
  default = {}
}

variable "image" {
  description = "Full image reference, e.g. ghcr.io/acme/app:1.2.3."
  type        = string
}

variable "image_pull_policy" {
  type    = string
  default = "IfNotPresent"
}

variable "command" {
  type    = list(string)
  default = null
}

variable "args" {
  type    = list(string)
  default = null
}

variable "replicas" {
  description = "Desired replicas (ignored when autoscaling.enabled: the HPA owns the count)."
  type        = number
  default     = 1
}

variable "ports" {
  type = list(object({
    name           = string
    container_port = number
    protocol       = optional(string, "TCP")
  }))
  default = []
}

variable "env" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "env_from_secrets" {
  description = "ENV_VAR => {secret, key}: values read from existing Kubernetes Secrets (secretKeyRef)."
  type = map(object({
    secret = string
    key    = string
  }))
  default = {}
}

variable "secret_env" {
  description = "ENV_VAR => value resolved by the cloud module. Stored in Secret <name>-env and injected with envFrom."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "files" {
  description = "Absolute path => content. Stored in ConfigMap <name>-files and mounted read-only with subPath."
  type        = map(string)
  default     = {}
}

variable "mounts" {
  description = "Existing Secrets/ConfigMaps to mount (e.g. keystores created by a pre-deploy step)."
  type = list(object({
    name       = string
    path       = string
    secret     = optional(string)
    config_map = optional(string)
    read_only  = optional(bool, true)
  }))
  default = []
}

variable "resources" {
  description = "Requests and limits are always set: it keeps the scheduler honest and the bill predictable."
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "256Mi" }
  }
}

variable "node_selector" {
  type    = map(string)
  default = {}
}

variable "tolerations" {
  type = list(object({
    key                = optional(string)
    operator           = optional(string, "Equal")
    value              = optional(string)
    effect             = optional(string)
    toleration_seconds = optional(number)
  }))
  default = []
}

variable "service_account_annotations" {
  description = "Cloud identity binding (eks.amazonaws.com/role-arn, azure.workload.identity/client-id, iam.gke.io/gcp-service-account)."
  type        = map(string)
  default     = {}
}

variable "pod_labels" {
  description = "Extra labels on the pod template only (e.g. azure.workload.identity/use)."
  type        = map(string)
  default     = {}
}

variable "service" {
  type = object({
    enabled = optional(bool, true)
    type    = optional(string, "ClusterIP")
    port    = optional(number)
  })
  default = {}
}

variable "probe" {
  description = "Liveness and readiness probe. port is a container port name or number (string)."
  type = object({
    type          = optional(string, "none") # none | http | tcp
    path          = optional(string, "/")
    port          = optional(string)
    initial_delay = optional(number, 5)
    period        = optional(number, 10)
  })
  default = {}
}

variable "network_policy" {
  description = "Default-deny policy for the pod with explicit allow rules."
  type = object({
    enabled          = optional(bool, false)
    allow_dns        = optional(bool, true)
    egress_https_any = optional(bool, false)
    ingress_from     = optional(list(map(string)), [])
    egress_to        = optional(list(map(string)), [])
    egress = optional(list(object({
      cidr     = string
      port     = number
      protocol = optional(string, "TCP")
    })), [])
  })
  default = {}
}

variable "autoscaling" {
  type = object({
    enabled      = optional(bool, false)
    min_replicas = optional(number, 1)
    max_replicas = optional(number, 3)
    target_cpu   = optional(number, 70)
  })
  default = {}
}

variable "security" {
  type = object({
    run_as_non_root           = optional(bool, false)
    run_as_user               = optional(number)
    run_as_group              = optional(number)
    fs_group                  = optional(number)
    read_only_root_filesystem = optional(bool, false)
  })
  default = {}
}

variable "wait_for_rollout" {
  description = "Block terraform apply until the Deployment is available."
  type        = bool
  default     = true
}

variable "rollout_timeout" {
  type    = string
  default = "5m"
}
