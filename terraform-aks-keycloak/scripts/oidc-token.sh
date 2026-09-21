#!/usr/bin/env bash
# Fetch a password-grant access token from the demo realm.
# Usage: ./scripts/oidc-token.sh [java-oidc|golang-oidc|public-web]
set -euo pipefail
CLIENT="${1:-java-oidc}"
ISSUER="$(terraform output -raw oidc_issuer_public)"

USER="$(terraform output -json demo_users | python3 -c 'import json,sys; print(json.load(sys.stdin)["usernames"][0])')"
PASS="$(terraform output -json demo_users | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"

SECRET=""
case "$CLIENT" in
  java-oidc) SECRET="$(terraform output -json oidc_client_secrets | python3 -c 'import json,sys; print(json.load(sys.stdin)["java"])')" ;;
  golang-oidc) SECRET="$(terraform output -json oidc_client_secrets | python3 -c 'import json,sys; print(json.load(sys.stdin)["golang"])')" ;;
  public-web) SECRET="" ;;
  *) echo "unknown client $CLIENT" >&2; exit 1 ;;
esac

ARGS=(
  -s
  -d "grant_type=password"
  -d "client_id=${CLIENT}"
  -d "username=${USER}"
  -d "password=${PASS}"
  -d "scope=openid profile email"
)
if [[ -n "$SECRET" ]]; then
  ARGS+=(-d "client_secret=${SECRET}")
fi

curl "${ARGS[@]}" "${ISSUER}/protocol/openid-connect/token"
echo
