#!/usr/bin/env bash
# =============================================================================
# devbox.sh — a Java / C++ / Go developer pod with SSH access from outside the cluster.
#
#   ./scripts/devbox.sh build                     # build images/devbox (kind: docker build + kind load; AKS: az acr build)
#   ./scripts/devbox.sh deploy [-k ~/.ssh/id_ed25519.pub]   # namespace, SSH key secret, StatefulSet + PVC, Service, policy
#   ./scripts/devbox.sh open [port]               # kind: port-forward localhost:<port> (default 2222) -> pod:2222
#   ./scripts/devbox.sh ssh                       # ssh in (LoadBalancer IP on cloud, port-forward on kind)
#   ./scripts/devbox.sh status | destroy
#
# Exposure: cloud context -> Service type LoadBalancer (port 22)   kind -> NodePort 30022 + `open`
#           USE_LB=true|false forces either. DEVBOX_IMAGE=<ref> overrides the image.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/common.sh"
NS=devbox; TAG="${DEVBOX_TAG:-1.0.0}"
load_config                                   # KIND_CLUSTER_NAME, AZ_* from app.config.yaml
require kubectl
ctx="$(kubectl config current-context)"
is_kind=false; [[ "$ctx" == kind-* ]] && is_kind=true
if [[ -n "${USE_LB:-}" ]]; then use_lb="$USE_LB"; elif $is_kind; then use_lb=false; else use_lb=true; fi

image_ref() {                       # devbox:<tag> locally, <acr>.azurecr.io/devbox:<tag> on Azure
  if [[ -n "${DEVBOX_IMAGE:-}" ]]; then echo "$DEVBOX_IMAGE"
  elif $is_kind; then echo "devbox:$TAG"
  else source "$HERE/azure/lib.sh"; azure_env >/dev/null; echo "$ACR_LOGIN_SERVER/devbox:$TAG"; fi
}
pubkey_file() {
  for f in "${1:-}" ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do [[ -n "$f" && -f "$f" ]] && { echo "$f"; return; }; done
  die "no SSH public key found — pass -k <file.pub> or run: ssh-keygen -t ed25519"
}
lb_ip() { kubectl -n $NS get svc devbox-ssh -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null; }

cmd="${1:-status}"; shift || true
case "$cmd" in
  build)
    img="$(image_ref)"
    if $is_kind; then
      require docker kind
      log "docker build $img (Temurin 25, Maven, Gradle, clang/gcc, Go — first build ≈ 5-10 min)"
      docker build --pull -t "$img" "$ROOT/images/devbox"
      kind load docker-image "$img" --name "$KIND_CLUSTER_NAME"
    else
      require az; source "$HERE/azure/lib.sh"; azure_env >/dev/null
      log "az acr build $img (cloud build, no local docker needed)"
      az acr build --registry "$AZ_ACR_NAME" --image "devbox:$TAG" --platform linux/amd64 "$ROOT/images/devbox" -o none
    fi
    ok "image ready: $img" ;;
  deploy)
    key=""; while getopts "k:" o; do case $o in k) key="$OPTARG";; *) ;; esac; done
    pub="$(pubkey_file "$key")"; img="$(image_ref)"
    log "context $ctx · image $img · key $pub · expose via $([[ $use_lb == true ]] && echo LoadBalancer || echo 'NodePort 30022 + port-forward')"
    kubectl apply -f "$ROOT/k8s/devbox/devbox.yaml" --dry-run=client -o yaml >/dev/null
    kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n $NS create secret generic devbox-ssh --from-file=authorized_keys="$pub" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "$ROOT/k8s/devbox/devbox.yaml"
    kubectl -n $NS set image statefulset/devbox devbox="$img"
    if [[ $use_lb == true ]]; then
      kubectl -n $NS patch svc devbox-ssh -p '{"spec":{"type":"LoadBalancer"}}'
    else
      kubectl -n $NS patch svc devbox-ssh -p '{"spec":{"type":"NodePort","ports":[{"name":"ssh","port":22,"targetPort":"ssh","nodePort":30022}]}}'
    fi
    log "waiting for the pod (volume + image pull)"
    kubectl -n $NS rollout status statefulset/devbox --timeout=5m
    "$0" status ;;
  status)
    kubectl -n $NS get pods -o wide; kubectl -n $NS get svc devbox-ssh pvc
    if [[ $use_lb == true ]]; then ip="$(lb_ip)"; [[ -n "$ip" ]] && ok "ssh dev@$ip   (host key fingerprint below)" || warn "LoadBalancer IP pending: kubectl -n $NS get svc devbox-ssh -w"
    else ok "kind: ./scripts/devbox.sh open   then   ssh -p 2222 dev@localhost"; fi
    kubectl -n $NS logs statefulset/devbox --tail=3 2>/dev/null | grep -E "host key|devbox ready" || true ;;
  open)
    port="${1:-2222}"; ok "ssh -p $port dev@localhost   (Ctrl+C stops the tunnel)"
    kubectl -n $NS port-forward svc/devbox-ssh "$port:22" ;;
  ssh)
    if [[ $use_lb == true ]]; then ip="$(lb_ip)"; [[ -n "$ip" ]] || die "no LoadBalancer IP yet"; exec ssh dev@"$ip"
    else kubectl -n $NS port-forward svc/devbox-ssh 2222:22 >/dev/null 2>&1 & pf=$!; sleep 2; ssh -p 2222 dev@localhost; kill $pf 2>/dev/null; fi ;;
  destroy)
    read -r -p "Delete namespace $NS including the home volume? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] && kubectl delete namespace $NS --wait=false && ok deleting || echo aborted ;;
  *) die "usage: $0 build | deploy [-k key.pub] | open [port] | ssh | status | destroy" ;;
esac
