# Architecture

## Goal

Provide a small command-line application that authenticates a human user with an OpenID Connect provider without embedding a browser or storing long-lived credentials.

## Flow

```text
Developer CLI
    |
    | 1. GET {issuer}/.well-known/openid-configuration
    v
OIDC Provider
    |
    | 2. POST device_authorization_endpoint
    |    client_id + scope
    v
CLI receives user_code + verification URI
    |
    | 3. User opens browser and signs in
    |
    | 4. CLI polls token_endpoint
    v
OIDC Provider returns access_token + id_token
    |
    | 5. CLI validates ID-token signature, issuer, time and audience
    |
    | 6. CLI optionally calls userinfo_endpoint
    v
Authenticated identity shown in terminal
```

## Main classes

- `OidcCliApplication` - Spring Boot entry point.
- `OidcProperties` - maps config file and environment variables.
- `OidcDeviceClient` - discovery, device flow, token polling, validation and UserInfo.
- `OidcCliRunner` - implements the `login`, `discover`, and `help` commands.

## Security choices

1. Public client is the default. A CLI installed on developer machines normally cannot safely keep a shared client secret.
2. HTTPS is required except for `localhost` development.
3. The OIDC discovery `issuer` must exactly match the configured issuer.
4. ID tokens are cryptographically verified by Spring Security/Nimbus.
5. The ID-token audience must contain the configured client ID.
6. Access tokens are not printed unless explicitly enabled for local debugging.
7. Tokens are kept only in process memory; this sample does not persist them to disk.

## Why Device Authorization Grant?

It works well for CLIs because the terminal displays a short code and URL while authentication happens in a normal browser. The CLI does not need to run a callback HTTP server or capture a password.
