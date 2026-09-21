locals {
  prefix = lower(replace(var.name_prefix, "/[^a-zA-Z0-9]/", ""))

  namespaces = {
    ingress   = "ingress-nginx"
    identity  = "identity"
    apps      = "apps"
    workspace = "workspace"
  }

  keycloak_service = "keycloak"
  keycloak_port    = 8080

  # In-cluster issuer used by Java/Go pods. Browser traffic uses the ingress host.
  keycloak_internal_url = "http://${local.keycloak_service}.${local.namespaces.identity}.svc.cluster.local:${local.keycloak_port}"
  realm_name            = "demo"

  java_client_id    = "java-oidc"
  golang_client_id  = "golang-oidc"
  public_client_id  = "public-web"
  service_client_id = "svc-client-credentials"

  java_app_port   = 8080
  golang_app_port = 8080
}
