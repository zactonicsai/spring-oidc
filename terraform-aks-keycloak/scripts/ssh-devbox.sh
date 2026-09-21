#!/usr/bin/env bash
set -euo pipefail
echo "Port-forwarding workspace/devbox 2222 -> 22"
echo "Password: $(terraform output -json devbox_ssh | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"
echo
kubectl -n workspace port-forward svc/devbox 2222:22
