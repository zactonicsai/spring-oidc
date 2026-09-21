resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "random_password" "keycloak_admin" {
  length  = 20
  special = false
}

resource "random_password" "java_client" {
  length  = 32
  special = false
}

resource "random_password" "golang_client" {
  length  = 32
  special = false
}

resource "random_password" "service_client" {
  length  = 32
  special = false
}

resource "random_password" "demo_user" {
  length  = 16
  special = false
}

resource "random_password" "devbox" {
  length  = 20
  special = false
}
