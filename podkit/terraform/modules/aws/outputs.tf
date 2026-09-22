output "cluster" {
  description = "Connection details of the existing cluster for the kubernetes provider."
  value = {
    host               = data.aws_eks_cluster.this.endpoint
    ca_certificate     = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token              = data.aws_eks_cluster_auth.this.token
    client_certificate = null
    client_key         = null
  }
  sensitive = true
}

output "service_account_annotations" {
  value = local.use_irsa ? { "eks.amazonaws.com/role-arn" = one(aws_iam_role.this[*].arn) } : {}
}

output "pod_labels" {
  value = {}
}

output "node_selector" {
  # With Karpenter use karpenter.sh/capacity-type = spot instead.
  value = var.spot ? { "eks.amazonaws.com/capacityType" = "SPOT" } : {}
}

output "tolerations" {
  value = []
}

output "secret_values" {
  description = "ENV_VAR => secret value (stored in the state: use an encrypted backend)."
  value       = { for k, v in data.aws_secretsmanager_secret_version.this : k => v.secret_string }
  sensitive   = true
}

output "identity_id" {
  description = "ARN of the IAM role bound to the ServiceAccount (null when create_identity is false)."
  value       = one(aws_iam_role.this[*].arn)
}
