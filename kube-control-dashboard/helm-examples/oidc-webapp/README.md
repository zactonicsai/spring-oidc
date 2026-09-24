# OIDC web app Helm chart

This is a deliberately small browser OIDC example. The app is static HTML served by Nginx, but it performs a real OIDC Authorization Code + PKCE login with Keycloak.

## Install

```bash
helm upgrade --install oidc-webapp . \
  --namespace oidc-demo \
  --create-namespace
```

Port-forward:

```bash
kubectl -n oidc-demo port-forward svc/oidc-webapp 8088:80
```

Open `http://localhost:8088/`.

The default values expect Keycloak at:

```text
http://localhost:8080/realms/k8s-demo
```

## Change OIDC settings

```bash
helm upgrade --install oidc-webapp . \
  --namespace oidc-demo \
  --create-namespace \
  --set oidc.issuer=https://keycloak.example.com/realms/apps \
  --set oidc.clientId=my-webapp \
  --set oidc.redirectUri=https://app.example.com/ \
  --set oidc.postLogoutRedirectUri=https://app.example.com/
```

For a browser public client, do not add a client secret to this chart. Configure the Keycloak client with **Client authentication Off**, Standard flow enabled, exact redirect URIs, and exact Web Origins.
