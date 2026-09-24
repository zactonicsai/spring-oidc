# Helm examples: Keycloak + OIDC web application

This folder adds two hands-on examples to Kube Control Dashboard:

1. `keycloak/` installs Keycloak with Helm.
2. `oidc-webapp/` is a tiny Helm chart that deploys an Nginx-hosted browser app using OpenID Connect Authorization Code + PKCE.

The local lab uses `kubectl port-forward`, so it works the same way on Docker Desktop, kind, EKS, GKE, AKS, OpenShift, IBM Cloud Kubernetes, and other clusters as long as `kubectl` can reach the cluster.

## Mental model

```text
Browser :8088
   |
   | 1. Login
   v
Keycloak :8080 ---- creates an authorization code
   |
   | 2. Browser exchanges code + PKCE verifier
   v
OIDC tokens kept in page memory
```

The web app is a **public OIDC client**. It does not contain a client secret. A browser cannot safely hide a client secret.

## Fast local lab

From the project root:

```bash
./helm-examples/keycloak/install-local.sh
```

In terminal 1:

```bash
kubectl -n keycloak port-forward svc/keycloak 8080:80
```

Create the realm and public OIDC client:

```bash
KEYCLOAK_ADMIN_PASSWORD='change-me-now' \
  ./helm-examples/keycloak/configure-demo-realm.sh
```

Install the demo web app:

```bash
helm upgrade --install oidc-webapp ./helm-examples/oidc-webapp \
  --namespace oidc-demo \
  --create-namespace
```

In terminal 2:

```bash
kubectl -n oidc-demo port-forward svc/oidc-webapp 8088:80
```

Open:

```text
http://localhost:8088/
```

Click **Sign in with Keycloak**.

## Create a test user

Open the Keycloak admin console:

```text
http://localhost:8080/
```

Then:

1. Sign in as `admin` with the password you used when installing Keycloak.
2. Switch to the `k8s-demo` realm.
3. Choose **Users** -> **Add user**.
4. Give the user a username and email.
5. Open the new user -> **Credentials** -> set a password.
6. Turn **Temporary** off if you do not want a password-change prompt.

## Why PKCE?

PKCE adds a one-time secret-like verifier that the browser creates for each login. The browser sends only a SHA-256 challenge during the first redirect. When the authorization code comes back, the browser must prove it has the original verifier before Keycloak returns tokens.

This helps protect a public browser client when an authorization code is intercepted.

## Production changes

The local lab deliberately favors simplicity. For production:

- Use HTTPS for both Keycloak and the web application.
- Use a real DNS name instead of `localhost`.
- Use exact redirect URIs and exact Web Origins.
- Store Keycloak admin and database passwords in Kubernetes Secrets or an external secret manager.
- Prefer an external managed PostgreSQL database for Keycloak.
- Run more than one Keycloak replica only after the database, cache, ingress, resource limits, and disruption behavior are designed for it.
- Use an ingress controller or Gateway API rather than `kubectl port-forward`.
- Do not persist access or refresh tokens in `localStorage`.

See `keycloak/values-production-example.yaml` for a starting point, not a drop-in production configuration.

## Useful Helm checks

```bash
helm list -A
helm status keycloak -n keycloak
helm get values keycloak -n keycloak
helm get manifest keycloak -n keycloak
helm history keycloak -n keycloak
helm template oidc-webapp ./helm-examples/oidc-webapp
```

Before changing chart versions:

```bash
helm show chart oci://registry-1.docker.io/bitnamicharts/keycloak
helm show values oci://registry-1.docker.io/bitnamicharts/keycloak > /tmp/keycloak-values.yaml
```

Compare your current values with the new chart values before upgrading.
