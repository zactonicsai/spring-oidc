#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ACR="$(terraform output -raw acr_name)"
SERVER="$(terraform output -raw acr_login_server)"

az acr login -n "$ACR"
az acr build -r "$ACR" -t devbox:27 -f apps/devbox/Dockerfile apps/devbox
echo
echo "Built ${SERVER}/devbox:27"
echo "Set in terraform.tfvars:"
echo "  devbox_image = \"${SERVER}/devbox:27\""
echo "Then: terraform apply"
