#!/usr/bin/env bash
# Phase 8 — secrets: see how the value gets in, rotate it, and prove pods picked it up.
#   ./scripts/08-secrets.sh show            # what Kubernetes stores (base64, NOT encryption)
#   ./scripts/08-secrets.sh rotate NEWVAL   # write a new API_TOKEN, re-deploy, verify
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
API="$(svc_var api K8S_NAME)"
case "${1:-show}" in
  show)
    kubectl -n "$APP_NAMESPACE" get secret "$API-secrets" -o yaml | grep -v -E 'annotations|last-applied|managed'
    echo; echo "base64 is an ENCODING, not encryption. Anyone with read access to Secrets can decode it:"
    kubectl -n "$APP_NAMESPACE" get secret "$API-secrets" -o jsonpath='{.data.API_TOKEN}' | base64 -d | sed 's/./*/g'; echo " (masked here)" ;;
  rotate)
    new="${2:?new value}"
    printf 'API_TOKEN=%s\n' "$new" > "$ROOT/secrets.env"; chmod 600 "$ROOT/secrets.env"
    log "re-rendering secrets and upgrading the release (checksum annotation forces a restart)"
    "$ROOT/scripts/04-deploy-helm.sh" >/dev/null
    kubectl -n "$APP_NAMESPACE" port-forward "svc/$API" 18081:80 >/dev/null 2>&1 & pid=$!; sleep 2
    curl -fsS http://127.0.0.1:18081/api/config; echo; kill $pid ;;
  *) die "usage: $0 show | rotate <value>" ;;
esac
