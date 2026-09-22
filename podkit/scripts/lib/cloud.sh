#!/usr/bin/env bash
# Cloud CLI helpers shared by the generated scripts. Source after common.sh.
# shellcheck shell=bash

# cloud_secret_get PROVIDER REF -> prints the secret value (uses AWS_REGION / AZURE_KEY_VAULT / GCP_PROJECT)
cloud_secret_get() {
  local provider=$1 ref=$2
  case "$provider" in
    aws)
      aws secretsmanager get-secret-value --secret-id "$ref" ${AWS_REGION:+--region "$AWS_REGION"} \
        --query SecretString --output text ;;
    azure)
      [[ -n "${AZURE_KEY_VAULT:-}" ]] || die "AZURE_KEY_VAULT is required to read secret '$ref' (spec.cloud.azure.keyVaultName)"
      az keyvault secret show --vault-name "$AZURE_KEY_VAULT" --name "$ref" --query value -o tsv ;;
    gcp)
      gcloud secrets versions access latest --secret="$ref" ${GCP_PROJECT:+--project "$GCP_PROJECT"} ;;
    *) die "unknown provider: $provider" ;;
  esac
}

# cloud_cli PROVIDER -> the CLI binary name
cloud_cli() {
  case "$1" in
    aws) echo aws ;; azure) echo az ;; gcp) echo gcloud ;; *) die "unknown provider: $1" ;;
  esac
}
