#!/usr/bin/env bash
# Azure phase 2 — build the images IN THE CLOUD with ACR Tasks (no local Docker needed) and store them in ACR.
#   Local alternative:  az acr login -n $AZ_ACR_NAME && docker build/tag/push
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
azure_env
for svc in $SERVICES; do
  repo="$(svc_var "$svc" IMAGE_REPO)"; tag="$(svc_var "$svc" IMAGE_TAG)"; ctx="$(svc_var "$svc" BUILD_CONTEXT)"; df="$(svc_var "$svc" DOCKERFILE)"
  log "az acr build $repo:$tag  (context $ctx) — ACR uploads the folder and builds it for you"
  az acr build --registry "$AZ_ACR_NAME" --image "$repo:$tag" --image "$repo:latest" \
    --file "$ROOT/$ctx/$df" --platform linux/amd64 "$ROOT/$ctx" --no-logs -o none
  ok "$ACR_LOGIN_SERVER/$repo:$tag"
done
log "images now in the registry:"
az acr repository list -n "$AZ_ACR_NAME" -o table
for svc in $SERVICES; do az acr repository show-tags -n "$AZ_ACR_NAME" --repository "$(svc_var "$svc" IMAGE_REPO)" -o tsv | sed "s/^/  $(svc_var "$svc" IMAGE_REPO):/"; done
