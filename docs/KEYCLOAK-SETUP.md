# Keycloak example setup

This project works with any standards-compliant provider that publishes an OIDC discovery document and supports OAuth 2.0 Device Authorization Grant.

## Keycloak client

Example values:

```text
Realm: demo
Client ID: oidc-cli
Client type: OpenID Connect
Client authentication: Off (public client)
OAuth 2.0 Device Authorization Grant: On
```

For a local Keycloak server at `http://localhost:8080`, the issuer is normally:

```text
http://localhost:8080/realms/demo
```

The application will discover the provider endpoints from:

```text
http://localhost:8080/realms/demo/.well-known/openid-configuration
```

## Local environment

```bash
cp .env.example .env
```

Then edit `.env`:

```bash
OIDC_ISSUER_URI=http://localhost:8080/realms/demo
OIDC_CLIENT_ID=oidc-cli
OIDC_CLIENT_AUTHENTICATION=NONE
OIDC_SCOPE="openid profile email"
```

Build and run:

```bash
./scripts/build.sh
./scripts/run.sh login
```

The CLI prints a verification URL and user code. Open the URL, sign in to Keycloak, enter the code if prompted, and approve the request.

## Confidential-client option

A developer CLI should usually be a public client. If your organization still requires client authentication, set one of:

```bash
OIDC_CLIENT_AUTHENTICATION=CLIENT_SECRET_POST
OIDC_CLIENT_SECRET=replace-me
```

or:

```bash
OIDC_CLIENT_AUTHENTICATION=CLIENT_SECRET_BASIC
OIDC_CLIENT_SECRET=replace-me
```

Do not commit real client secrets to Git.
