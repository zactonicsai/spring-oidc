#!/usr/bin/env bash
# The whole Azure path in one go (~15 minutes, creates billable resources).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -euo pipefail
"$HERE/00-login.sh"
"$HERE/01-create-resources.sh"
"$HERE/02-build-push-images.sh"
"$HERE/03-create-aks.sh"
"$HERE/04-get-credentials.sh"
"$HERE/08-secrets.sh" create
"$HERE/08-secrets.sh" set API_TOKEN "azure-$(date +%s)"
"$HERE/08-secrets.sh" deploy        # deploys the chart with the Key Vault secret
"$HERE/06-test.sh"
echo; echo "Optional: ./scripts/azure/10-create-vm.sh (plain VM path)  |  ./scripts/azure/99-destroy.sh when finished"
