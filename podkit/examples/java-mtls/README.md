# java-mtls example

Two tiny Java programs that only speak to each other over mutual TLS:

* `Server.java` – HTTPS server that **requires** a client certificate.
* `Client.java` – calls the server every `INTERVAL_SECONDS` with its own certificate.

Both read the keystore and truststore that podkit mounts from Secrets
(`KEYSTORE_PATH`, `TRUSTSTORE_PATH` and the matching `*_PASSWORD` variables).

```bash
docker build -t ghcr.io/acme/java-mtls:1.0.0 examples/java-mtls   # push it to your registry
python -m podgen generate examples/java-server.yaml examples/java-client.yaml --provider aws
scripts/deploy.sh build/aws/java-server      # pre-deploy step: CA + server keystore + truststore
scripts/deploy.sh build/aws/java-client      # pre-deploy step: client keystore (same CA)
kubectl -n apps logs deploy/java-client      # "200 hello CN=java-client from java-server-..."
```

How it works: the pre-deploy step creates one CA per namespace (Secret `podkit-mtls-ca`),
issues a certificate per pod (Secret `<name>-keystore`, extendedKeyUsage `serverAuth`+`clientAuth`
for servers, `clientAuth` only for clients) and builds one shared truststore (Secret
`podkit-mtls-truststore`). Rotate a pod's certificate with `build/<cloud>/<name>/configure.sh -e rotate=true`
(Ansible) or `build/<cloud>/<name>/configure.sh ROTATE=true` (shell).
