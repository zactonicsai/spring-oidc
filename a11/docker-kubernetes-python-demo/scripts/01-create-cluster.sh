#!/usr/bin/env bash
# Phase 1 — create the local kind cluster + install metrics-server (needed by the autoscaler).
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
CLUSTER_NAME="${CLUSTER_NAME:-$KIND_CLUSTER_NAME}"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  ok "kind cluster '$CLUSTER_NAME' already exists"
else
  log "Creating kind cluster '$CLUSTER_NAME' from $KIND_CONFIG"
  kind create cluster --name "$CLUSTER_NAME" --config "$ROOT/$KIND_CONFIG"
fi
kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null
kubectl cluster-info
kubectl get nodes -o wide

# metrics-server = the cluster's "thermometer". Without it `kubectl top` and the
# HorizontalPodAutoscaler have no CPU numbers to look at. kind's kubelets use
# self-signed certs, so the standard manifest needs --kubelet-insecure-tls.
if ! kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
  log "Installing metrics-server"
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi
kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s
ok "cluster '$CLUSTER_NAME' is ready (network policies are enforced by kind's built-in kube-network-policies)"
