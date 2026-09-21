#!/usr/bin/env bash
# Phase 0 — make sure every tool exists and Docker is running.
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
log "Checking required tools"
require docker kind kubectl helm curl python3
docker info >/dev/null 2>&1 || die "Docker is installed but not running — start Docker Desktop / dockerd"
ok "docker  $(docker --version | cut -d, -f1)"
ok "kind    $(kind --version)"
ok "kubectl $(kubectl version --client -o json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["clientVersion"]["gitVersion"])' 2>/dev/null || kubectl version --client | head -1)"
ok "helm    $(helm version --short)"
case "$(helm version --short)" in v4*) ;; *) warn "Helm 4 is current (Helm 3 reached end of life in 2026). Scripts still work on v3." ;; esac
log "Validating app.config.yaml"
load_config
ok "config OK: app=$APP_NAME version=$APP_VERSION services=[$SERVICES] namespace=$APP_NAMESPACE"
python3 "$ROOT/tools/appconfig.py" show -c "$CONFIG_FILE"
