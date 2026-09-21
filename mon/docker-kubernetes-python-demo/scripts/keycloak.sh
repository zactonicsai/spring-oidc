#!/usr/bin/env bash
# =============================================================================
# keycloak.sh — deploy Keycloak (2+ replicas, Postgres-backed) and expose port 80 -> 8080.
#
#   ./scripts/keycloak.sh deploy            # namespace, secrets (random passwords), postgres, keycloak, HPA(min 2), PDB, policies
#   ./scripts/keycloak.sh status            # pods / service / hpa + the URL
#   ./scripts/keycloak.sh open [port]       # kind: port-forward localhost:<port> (default 8080) -> keycloak:80
#   ./scripts/keycloak.sh admin             # print the admin username/password
#   ./scripts/keycloak.sh realm             # (re)import k8s/keycloak/realm-demo.json with kcadm (users alice/bob/carol, clients cli-java, cli-go)
#   ./scripts/keycloak.sh url               # print the base URL (LB IP or localhost port-forward)
#   ./scripts/keycloak.sh destroy           # delete the namespace (and the database volume!)
#
# Exposure:  AKS/cloud context -> Service type LoadBalancer (public IP on port 80)
#            kind context       -> Service type NodePort 30080 + `open` port-forward
#            USE_LB=true / USE_LB=false forces either.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/common.sh"
NS=keycloak; MAN="$ROOT/k8s/keycloak"
require kubectl
ctx="$(kubectl config current-context)"
if [[ -n "${USE_LB:-}" ]]; then use_lb="$USE_LB"; elif [[ "$ctx" == kind-* ]]; then use_lb=false; else use_lb=true; fi

randpw() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; }

case "${1:-status}" in
  deploy)
    log "context: $ctx  (expose via $([[ $use_lb == true ]] && echo LoadBalancer || echo 'NodePort 30080 + port-forward'))"
    kubectl apply -f "$MAN/00-namespace.yaml"
    if ! kubectl -n $NS get secret keycloak-admin >/dev/null 2>&1; then
      kubectl -n $NS create secret generic keycloak-admin --from-literal=username=admin --from-literal=password="$(randpw)"
      ok "admin secret created (show it: $0 admin)"
    fi
    if ! kubectl -n $NS get secret keycloak-db >/dev/null 2>&1; then
      kubectl -n $NS create secret generic keycloak-db --from-literal=username=keycloak --from-literal=database=keycloak --from-literal=password="$(randpw)"
      ok "database secret created"
    fi
    kubectl -n $NS create configmap keycloak-realm --from-file=realm-demo.json="$MAN/realm-demo.json" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "$MAN/10-postgres.yaml" -f "$MAN/20-keycloak.yaml" -f "$MAN/30-network-policy.yaml"
    if [[ $use_lb == true ]]; then
      kubectl -n $NS patch svc keycloak -p '{"spec":{"type":"LoadBalancer"}}'
    else
      kubectl -n $NS patch svc keycloak -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"targetPort":"http","nodePort":30080}]}}'
    fi
    log "waiting for the database"
    kubectl -n $NS rollout status statefulset/keycloak-db --timeout=3m
    log "waiting for 2 Keycloak replicas (first start builds the server + migrates the DB: 1-3 minutes)"
    kubectl -n $NS rollout status deployment/keycloak --timeout=8m
    "$0" status ;;
  status)
    kubectl -n $NS get pods -o wide
    kubectl -n $NS get svc keycloak keycloak-headless keycloak-db
    kubectl -n $NS get hpa,pdb
    if [[ $use_lb == true ]]; then
      ip="$(kubectl -n $NS get svc keycloak -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
      [[ -n "$ip" ]] && ok "Keycloak: http://$ip/   (admin console: http://$ip/admin)" || warn "LoadBalancer IP pending: kubectl -n $NS get svc keycloak -w"
    else
      ok "kind: run  $0 open  then browse http://localhost:8080/admin   (NodePort 30080 on the node containers)"
    fi
    echo "  replicas ready: $(kubectl -n $NS get deploy keycloak -o jsonpath='{.status.readyReplicas}')/$(kubectl -n $NS get deploy keycloak -o jsonpath='{.spec.replicas}')" ;;
  open)
    port="${2:-8080}"; ok "http://localhost:$port/admin  (Ctrl+C to stop)"
    kubectl -n $NS port-forward svc/keycloak "$port:80" ;;
  admin)
    echo "username: $(kubectl -n $NS get secret keycloak-admin -o jsonpath='{.data.username}' | base64 -d)"
    echo "password: $(kubectl -n $NS get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)" ;;
  url)
    if [[ $use_lb == true ]]; then echo "http://$(kubectl -n $NS get svc keycloak -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"; else echo "http://localhost:8080"; fi ;;
  realm)
    # Re-apply the demo realm on a running server (first deploy imports it automatically via --import-realm).
    pw="$(kubectl -n $NS get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)"
    pod="$(kubectl -n $NS get pod -l app.kubernetes.io/component=server -o jsonpath='{.items[0].metadata.name}')"
    kubectl -n $NS cp "$MAN/realm-demo.json" "$pod:/tmp/realm-demo.json"
    kubectl -n $NS exec "$pod" -- bash -c "
      /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password '$pw' >/dev/null &&
      if /opt/keycloak/bin/kcadm.sh get realms/demo >/dev/null 2>&1; then
        /opt/keycloak/bin/kcadm.sh create partialImport -r demo -s ifResourceExists=OVERWRITE -o -f /tmp/realm-demo.json >/dev/null && echo 'realm demo updated (partial import, OVERWRITE)'
      else
        /opt/keycloak/bin/kcadm.sh create realms -f /tmp/realm-demo.json && echo 'realm demo created'
      fi; rm -f /tmp/realm-demo.json"
    ok "realm ready: $("$0" url)/realms/demo/.well-known/openid-configuration" ;;
  destroy)
    read -r -p "Delete namespace $NS including the Postgres volume? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] && kubectl delete namespace $NS --wait=false && ok "deleting" || echo aborted ;;
  *) die "usage: $0 deploy | status | open [port] | admin | realm | url | destroy" ;;
esac
