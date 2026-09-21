#!/usr/bin/env bash
# One command: check -> cluster -> build -> load -> deploy -> test.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -euo pipefail
"$HERE/00-check-prereqs.sh"
"$HERE/01-create-cluster.sh"
"$HERE/02-build-images.sh"
"$HERE/03-load-images.sh"
"$HERE/04-deploy-helm.sh"
"$HERE/05-test.sh"
echo; echo "Done. Next: ./scripts/06-port-forward.sh  then open http://localhost:8080"
