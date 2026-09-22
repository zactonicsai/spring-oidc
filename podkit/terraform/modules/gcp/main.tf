# GCP (GKE): reads the existing cluster, resolves Secret Manager values and optionally creates a
# Google service account bound to the pod's ServiceAccount (Workload Identity Federation for GKE).

terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
}

data "google_client_config" "this" {}

data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.location
  project  = var.project
}

locals {
  # Service account ids: 6-30 chars, lowercase letters, digits and hyphens, starting with a letter.
  account_id = trimsuffix(substr(replace(lower("pk-${var.name}-${var.namespace}"), "/[^a-z0-9-]/", "-"), 0, 30), "-")
  ksa_member = "serviceAccount:${var.project}.svc.id.goog[${var.namespace}/${var.service_account_name}]"
}

# ---- secrets ------------------------------------------------------------------------------------

data "google_secret_manager_secret_version" "this" {
  for_each = var.secrets
  project  = var.project
  secret   = each.value
}

# ---- identity -----------------------------------------------------------------------------------

resource "google_service_account" "this" {
  count        = var.create_identity ? 1 : 0
  project      = var.project
  account_id   = local.account_id
  display_name = "podkit ${var.namespace}/${var.name} on ${var.cluster_name}"
}

resource "google_service_account_iam_member" "workload_identity" {
  count              = var.create_identity ? 1 : 0
  service_account_id = google_service_account.this[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.ksa_member
}

resource "google_secret_manager_secret_iam_member" "read" {
  for_each  = var.create_identity ? var.secrets : {}
  project   = var.project
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.this[0].email}"
}

resource "google_project_iam_member" "extra" {
  for_each = var.create_identity ? toset(var.extra_roles) : toset([])
  project  = var.project
  role     = each.value
  member   = "serviceAccount:${google_service_account.this[0].email}"
}
