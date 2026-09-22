#!/usr/bin/env bash
# Shell twin of ansible/playbooks/java-keystore.yml: issue a certificate from a shared CA and
# publish a Java keystore + truststore as Secrets. Idempotent; ROTATE=true reissues.
#
# Inputs (env, from build/<provider>/<name>/configure.env):
#   NAMESPACE SUBJECT_NAME DNS_NAMES(csv) IS_SERVER CA_SECRET KEYSTORE_SECRET TRUSTSTORE_SECRET
#   VALIDITY_DAYS ROTATE RESTART_DEPLOYMENTS(csv)
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
apply_overrides "$@"
require_cmd kubectl openssl keytool base64

: "${NAMESPACE:?NAMESPACE is required}" "${SUBJECT_NAME:?SUBJECT_NAME is required}"
CA_SECRET="${CA_SECRET:-podkit-mtls-ca}"
KEYSTORE_SECRET="${KEYSTORE_SECRET:-$SUBJECT_NAME-keystore}"
TRUSTSTORE_SECRET="${TRUSTSTORE_SECRET:-podkit-mtls-truststore}"
IS_SERVER="${IS_SERVER:-false}"
DNS_NAMES="${DNS_NAMES:-}"
VALIDITY_DAYS="${VALIDITY_DAYS:-365}"
ROTATE="${ROTATE:-false}"
RESTART_DEPLOYMENTS="${RESTART_DEPLOYMENTS:-}"
CA_ALIAS="podkit-ca"
LABELS="app.kubernetes.io/managed-by=podkit,podkit.dev/component=mtls"

ca_exists=false ks_exists=false ts_exists=false
secret_exists "$NAMESPACE" "$CA_SECRET" && ca_exists=true
secret_exists "$NAMESPACE" "$KEYSTORE_SECRET" && ks_exists=true
secret_exists "$NAMESPACE" "$TRUSTSTORE_SECRET" && ts_exists=true

issue_needed=false ts_needed=false
[[ "$ROTATE" == "true" || "$ks_exists" == "false" || "$ca_exists" == "false" ]] && issue_needed=true
[[ "$ROTATE" == "true" || "$ts_exists" == "false" || "$ca_exists" == "false" ]] && ts_needed=true
log "$SUBJECT_NAME ($([[ "$IS_SERVER" == "true" ]] && echo server || echo client)): CA $([[ $ca_exists == true ]] && echo exists || echo 'will be created'), keystore $([[ $issue_needed == true ]] && echo 'will be issued' || echo kept), truststore $([[ $ts_needed == true ]] && echo 'will be built' || echo kept)"
if [[ "$issue_needed" == "false" && "$ts_needed" == "false" ]]; then
  log "nothing to do (ROTATE=true reissues)"; exit 0
fi

work="$(mktemp -d -t podkit-tls.XXXXXX)"
trap 'rm -rf "$work"' EXIT
cd "$work"

# ---- CA ---------------------------------------------------------------------------------------
if [[ "$ca_exists" == "true" ]]; then
  # shellcheck disable=SC2094  # the first argument is a Secret key, not the file
  secret_key "$NAMESPACE" "$CA_SECRET" ca.crt > ca.crt
  # shellcheck disable=SC2094
  secret_key "$NAMESPACE" "$CA_SECRET" ca.key > ca.key
else
  log "creating CA secret $NAMESPACE/$CA_SECRET"
  openssl ecparam -name prime256v1 -genkey -noout -out ca.key
  openssl req -x509 -new -key ca.key -sha256 -days $((VALIDITY_DAYS * 5)) \
    -subj "/CN=podkit mTLS CA ($NAMESPACE)" -out ca.crt
  apply_secret "$NAMESPACE" "$CA_SECRET" "$LABELS,podkit.dev/role=ca" --from-file=ca.crt --from-file=ca.key
fi
chmod 0600 ca.key

# ---- leaf certificate + keystore -----------------------------------------------------------
if [[ "$issue_needed" == "true" ]]; then
  if [[ -n "$DNS_NAMES" ]]; then san="DNS:${DNS_NAMES//,/,DNS:}"; else san="DNS:$SUBJECT_NAME"; fi
  eku="clientAuth"; [[ "$IS_SERVER" == "true" ]] && eku="serverAuth, clientAuth"
  cat > ext.cnf <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $SUBJECT_NAME
[v3_ext]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = $eku
subjectAltName = $san
CNF
  STORE_PASS="$(openssl rand -hex 16)"; export STORE_PASS
  openssl ecparam -name prime256v1 -genkey -noout -out tls.key
  openssl req -new -key tls.key -config ext.cnf -out tls.csr
  openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days "$VALIDITY_DAYS" -sha256 -extfile ext.cnf -extensions v3_ext -out tls.crt 2>/dev/null
  openssl pkcs12 -export -in tls.crt -inkey tls.key -certfile ca.crt -name "$SUBJECT_NAME" \
    -out keystore.p12 -passout env:STORE_PASS
  keytool -importkeystore -noprompt -srckeystore keystore.p12 -srcstoretype PKCS12 -srcstorepass:env STORE_PASS \
    -destkeystore keystore.jks -deststoretype JKS -deststorepass:env STORE_PASS -destkeypass:env STORE_PASS 2>/dev/null
  printf '%s' "$STORE_PASS" > keystore.password
  log "storing keystore secret $NAMESPACE/$KEYSTORE_SECRET (SAN: $san)"
  apply_secret "$NAMESPACE" "$KEYSTORE_SECRET" "$LABELS,podkit.dev/role=keystore,app.kubernetes.io/name=$SUBJECT_NAME" \
    --from-file=keystore.jks --from-file=keystore.password --from-file=tls.crt
  rm -f keystore.p12 tls.key tls.csr keystore.password
fi

# ---- truststore ---------------------------------------------------------------------------------
if [[ "$ts_needed" == "true" ]]; then
  STORE_PASS="$(openssl rand -hex 16)"; export STORE_PASS
  keytool -importcert -noprompt -alias "$CA_ALIAS" -file ca.crt -keystore truststore.jks -storetype JKS -storepass:env STORE_PASS 2>/dev/null
  printf '%s' "$STORE_PASS" > truststore.password
  log "storing truststore secret $NAMESPACE/$TRUSTSTORE_SECRET"
  apply_secret "$NAMESPACE" "$TRUSTSTORE_SECRET" "$LABELS,podkit.dev/role=truststore" \
    --from-file=truststore.jks --from-file=truststore.password --from-file=ca.crt
fi

# ---- roll running pods so they load the new material -----------------------------------------------
[[ "$issue_needed" == "true" && -n "$RESTART_DEPLOYMENTS" ]] && restart_deployments "$NAMESPACE" "$RESTART_DEPLOYMENTS"
log "done: pods read KEYSTORE_PATH / TRUSTSTORE_PATH and the *_PASSWORD env vars"
