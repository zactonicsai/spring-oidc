resource "kubernetes_namespace_v1" "identity" {
  metadata {
    name = local.namespaces.identity
    labels = {
      "app.kubernetes.io/part-of" = "aks-keycloak-oidc"
    }
  }
}

resource "kubernetes_namespace_v1" "apps" {
  metadata {
    name = local.namespaces.apps
    labels = {
      "app.kubernetes.io/part-of" = "aks-keycloak-oidc"
    }
  }
}

resource "kubernetes_namespace_v1" "workspace" {
  metadata {
    name = local.namespaces.workspace
    labels = {
      "app.kubernetes.io/part-of" = "aks-keycloak-oidc"
    }
  }
}
