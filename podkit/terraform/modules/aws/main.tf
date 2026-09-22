# AWS (EKS): reads the existing cluster, resolves Secrets Manager values and optionally creates
# an IAM role for the pod (IRSA or EKS Pod Identity).

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 7.0"
    }
  }
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

locals {
  oidc_issuer = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  oidc_host   = replace(local.oidc_issuer, "https://", "")
  use_irsa    = var.create_identity && var.identity_mode == "irsa"
  use_pod_id  = var.create_identity && var.identity_mode == "pod-identity"
  role_name   = substr("${var.cluster_name}-${var.namespace}-${var.name}", 0, 64)
  tags        = merge({ "podkit/workload" = "${var.namespace}/${var.name}", "podkit/cluster" = var.cluster_name }, var.tags)
}

# ---- secrets ------------------------------------------------------------------------------------

data "aws_secretsmanager_secret" "this" {
  for_each = var.secrets
  name     = each.value
}

data "aws_secretsmanager_secret_version" "this" {
  for_each  = var.secrets
  secret_id = data.aws_secretsmanager_secret.this[each.key].id
}

# ---- identity -----------------------------------------------------------------------------------

# IRSA: the cluster's OIDC issuer must be registered as an IAM identity provider
# (eksctl utils associate-iam-oidc-provider / aws_iam_openid_connect_provider).
data "aws_iam_openid_connect_provider" "this" {
  count = local.use_irsa ? 1 : 0
  url   = local.oidc_issuer
}

data "aws_iam_policy_document" "trust" {
  count = var.create_identity ? 1 : 0

  dynamic "statement" {
    for_each = local.use_irsa ? [1] : []
    content {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      principals {
        type        = "Federated"
        identifiers = [data.aws_iam_openid_connect_provider.this[0].arn]
      }
      condition {
        test     = "StringEquals"
        variable = "${local.oidc_host}:sub"
        values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
      }
      condition {
        test     = "StringEquals"
        variable = "${local.oidc_host}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.use_pod_id ? [1] : []
    content {
      actions = ["sts:AssumeRole", "sts:TagSession"]
      principals {
        type        = "Service"
        identifiers = ["pods.eks.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "this" {
  count              = var.create_identity ? 1 : 0
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.trust[0].json
  tags               = local.tags
}

data "aws_iam_policy_document" "secrets" {
  count = var.create_identity && length(var.secrets) > 0 ? 1 : 0
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [for s in data.aws_secretsmanager_secret.this : s.arn]
  }
}

resource "aws_iam_role_policy" "secrets" {
  count  = var.create_identity && length(var.secrets) > 0 ? 1 : 0
  name   = "read-secrets"
  role   = aws_iam_role.this[0].id
  policy = data.aws_iam_policy_document.secrets[0].json
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each   = var.create_identity ? toset(var.extra_policy_arns) : toset([])
  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

# Pod Identity: no ServiceAccount annotation needed; the association does the binding.
resource "aws_eks_pod_identity_association" "this" {
  count           = local.use_pod_id ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.this[0].arn
  tags            = local.tags
}
