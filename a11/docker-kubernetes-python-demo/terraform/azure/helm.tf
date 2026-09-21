# Same chart, same values as local — plus a public LoadBalancer and secrets from var.secrets.
resource "helm_release" "app" {
  count            = var.deploy_helm ? 1 : 0
  name             = local.name
  namespace        = module.app.namespace
  create_namespace = true
  chart            = "${local.root}/helm/python-demo"
  wait             = true
  timeout          = 600

  values = [
    yamlencode(merge(module.app.helm_values, {
      publicServiceType         = "LoadBalancer"
      publicServiceSourceRanges = var.public_service_source_ranges
      secrets                   = local.secrets_by_service
    }))
  ]

  depends_on = [
    azurerm_role_assignment.aks_acr_pull, # cluster must be allowed to pull ...
    terraform_data.acr_build,             # ... and the images must exist
  ]
}
