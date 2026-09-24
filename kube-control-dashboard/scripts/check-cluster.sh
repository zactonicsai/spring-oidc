#!/usr/bin/env bash
set -Eeuo pipefail

echo "== Tool versions =="
kubectl version --client=true || true
helm version --short || true

echo
echo "== Current context =="
kubectl config current-context

echo
echo "== API server =="
kubectl version -o yaml

echo
echo "== Nodes =="
kubectl get nodes -o wide

echo
echo "== Deployments =="
kubectl get deployments -A

echo
echo "== Pods not Running/Succeeded =="
kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' || true

echo
echo "== Warning events =="
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp || true
