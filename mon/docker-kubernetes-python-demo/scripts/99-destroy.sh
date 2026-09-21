#!/usr/bin/env bash
# Delete the whole kind cluster (Docker itself stays).
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
kind delete cluster --name "${CLUSTER_NAME:-$KIND_CLUSTER_NAME}"
ok "cluster deleted"
