#!/usr/bin/env bash
# Point kubectl at an existing EKS, AKS or GKE cluster. Kept for compatibility; same as `podkit cluster login`.
#   cluster-login.sh -p aws -c CLUSTER -r REGION | -p azure -c CLUSTER -g RESOURCE_GROUP | -p gcp -c CLUSTER -P PROJECT -l LOCATION
set -Eeuo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../bin/podkit" cluster login "$@"
