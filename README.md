# Spring OIDC CLI

A small Java Spring Boot command-line application that authenticates a user with **OpenID Connect (OIDC)** using the **OAuth 2.0 Device Authorization Grant**.

The tool is designed for developer workstations and automation-friendly environments. OIDC settings can come from `application.yml`, an external YAML file, or environment variables.

## What it does

1. Reads the OIDC issuer and client configuration.
2. Loads `/.well-known/openid-configuration` from the issuer.
3. Starts Device Authorization Grant.
4. Prints a browser URL and user code.
5. Polls the provider while the user signs in.
6. Receives an access token and OIDC ID token.
7. Verifies the ID token using Spring Security/Nimbus.
8. Checks that the token audience contains the configured client ID.
9. Prints basic identity claims and, when available, the OIDC UserInfo response.
10. Keeps tokens in memory and does not print the access token by default.

## Requirements

- Java 17 or newer
- Maven 3.9+
- An OIDC provider with Device Authorization Grant enabled

Spring Boot version in this sample: **3.5.15**.

## Project layout

```text
spring-oidc-cli/
├── pom.xml
├── README.md
├── .env.example
├── config/
│   └── application-example.yml
├── docs/
│   ├── ARCHITECTURE.md
│   └── KEYCLOAK-SETUP.md
├── scripts/
│   ├── build.sh
│   └── run.sh
└── src/
    ├── main/
    │   ├── java/com/example/oidccli/
    │   │   ├── OidcCliApplication.java
    │   │   ├── cli/OidcCliRunner.java
    │   │   ├── config/OidcProperties.java
    │   │   └── oidc/
    │   │       ├── DeviceAuthorizationResponse.java
    │   │       ├── OidcDeviceClient.java
    │   │       ├── OidcDiscovery.java
    │   │       └── TokenResponse.java
    │   └── resources/application.yml
    └── test/
```

## Quick start

### 1. Configure environment variables

For local development:

```bash
cp .env.example .env
```

Edit `.env`:

```bash
OIDC_ISSUER_URI=http://localhost:8080/realms/demo
OIDC_CLIENT_ID=oidc-cli
OIDC_CLIENT_SECRET=
OIDC_SCOPE="openid profile email"
OIDC_CLIENT_AUTHENTICATION=NONE
OIDC_VERIFY_ID_TOKEN=true
OIDC_PRINT_ACCESS_TOKEN=false
```

> `.env` is ignored by Git. `scripts/run.sh` loads it before starting Spring Boot.

### 2. Build

```bash
./scripts/build.sh
```

Or directly:

```bash
mvn clean verify
```

### 3. Inspect provider discovery

```bash
./scripts/run.sh discover
```

Example output:

```json
{
  "issuer" : "http://localhost:8080/realms/demo",
  "token_endpoint" : "...",
  "jwks_uri" : "...",
  "userinfo_endpoint" : "...",
  "device_authorization_endpoint" : "..."
}
```

### 4. Log in

```bash
./scripts/run.sh login
```

The terminal will show something like:

```text
OIDC login started
==================
1. Open: https://identity.example.com/device?user_code=ABCD-EFGH
2. If asked, enter code: ABCD-EFGH
3. Sign in and approve the request.

Waiting for approval...
```

After approval:

```text
Authentication successful.
ID token signature/issuer/time/audience validation: OK

Identity claims:
  sub: 12345678
  preferred_username: developer1
  name: Developer One
  email: developer1@example.com
```

## Commands

```bash
java -jar target/spring-oidc-cli-0.1.0.jar login
java -jar target/spring-oidc-cli-0.1.0.jar discover
java -jar target/spring-oidc-cli-0.1.0.jar help
```

`login` is the default if no command is supplied.

## Configuration

Spring Boot environment variables override the values in `src/main/resources/application.yml`.

| Environment variable | Default | Purpose |
|---|---|---|
| `OIDC_ISSUER_URI` | `http://localhost:8080/realms/demo` | Exact OIDC issuer URL |
| `OIDC_CLIENT_ID` | `oidc-cli` | OIDC client ID |
| `OIDC_CLIENT_SECRET` | empty | Optional confidential-client secret |
| `OIDC_SCOPE` | `openid profile email` | Space-separated scopes; must include `openid` |
| `OIDC_CLIENT_AUTHENTICATION` | `NONE` | `NONE`, `CLIENT_SECRET_POST`, or `CLIENT_SECRET_BASIC` |
| `OIDC_POLL_TIMEOUT` | `PT5M` | Maximum login polling time as a Java duration |
| `OIDC_VERIFY_ID_TOKEN` | `true` | Verify ID-token signature, issuer, time, and audience |
| `OIDC_PRINT_ACCESS_TOKEN` | `false` | Print access token; local debugging only |
| `OIDC_ALLOW_HTTP_LOCALHOST` | `true` | Allow HTTP only for localhost development |

### Example: export variables manually

```bash
export OIDC_ISSUER_URI="https://login.example.com/realms/developers"
export OIDC_CLIENT_ID="developer-cli"
export OIDC_SCOPE="openid profile email"
export OIDC_CLIENT_AUTHENTICATION="NONE"

java -jar target/spring-oidc-cli-0.1.0.jar login
```

### Example: external Spring YAML file

A sample is included at `config/application-example.yml`.

```bash
java -jar target/spring-oidc-cli-0.1.0.jar login \
  --spring.config.additional-location=file:./config/application-example.yml
```

Environment variables still take precedence over the YAML values.

## OIDC provider requirements

Your provider needs to:

- expose an OIDC discovery document;
- support the `openid` scope;
- advertise `device_authorization_endpoint`;
- allow Device Authorization Grant for the configured client;
- return an ID token for an OIDC login.

For Keycloak, see [`docs/KEYCLOAK-SETUP.md`](docs/KEYCLOAK-SETUP.md).

## Public client vs client secret

For a CLI installed on developer computers, prefer:

```bash
OIDC_CLIENT_AUTHENTICATION=NONE
```

A client secret copied to many laptops is not truly secret. If your identity provider requires a confidential client, this sample also supports `CLIENT_SECRET_POST` and `CLIENT_SECRET_BASIC`, but secret storage then becomes your responsibility.

## Security notes

- Use HTTPS for real identity providers.
- Plain HTTP is accepted only for `localhost` by default.
- The issuer returned by discovery must exactly match `OIDC_ISSUER_URI`.
- The ID token is validated with Spring Security's `JwtDecoder`/Nimbus support.
- The ID-token audience must include `OIDC_CLIENT_ID`.
- Access tokens are not printed unless explicitly enabled.
- Tokens are not written to files by this sample.
- Never put a production client secret in `application.yml`, `.env.example`, source code, or Git.

## Troubleshooting

### `OIDC provider does not advertise device_authorization_endpoint`

Device Authorization Grant is not enabled or is not supported by the provider/client. Enable the device flow in your identity provider.

### `OIDC issuer mismatch`

Use the exact issuer value from the provider's discovery document. Do not guess the issuer from the login page URL.

### `No id_token was returned`

Make sure `OIDC_SCOPE` contains `openid` and the provider treats the client as an OpenID Connect client.

### `ID token audience does not contain expected client ID`

The token was issued for a different client, or the provider's audience mapping needs adjustment.

### HTTP issuer rejected

For production use HTTPS. Localhost HTTP is allowed only when:

```bash
OIDC_ALLOW_HTTP_LOCALHOST=true
```

### Token request keeps waiting

Complete the login in the browser. The CLI follows the server-provided polling interval and handles the standard `authorization_pending` and `slow_down` responses.

## Production extensions

This intentionally stays small. Common next steps are:

- encrypted refresh-token storage in the OS keychain;
- token refresh support;
- `logout` and token-revocation commands;
- calling your protected REST API with the access token;
- role/group claim checks;
- structured JSON CLI output;
- integration with Spring Shell for many subcommands;
- provider-specific configuration profiles for Keycloak, Entra ID, Okta, or Auth0.

## References

- Spring Security OAuth2/OIDC client documentation: https://docs.spring.io/spring-security/reference/servlet/oauth2/
- OpenID Connect Discovery 1.0: https://openid.net/specs/openid-connect-discovery-1_0.html
- OAuth 2.0 Device Authorization Grant (RFC 8628): https://www.rfc-editor.org/rfc/rfc8628.html
- Keycloak OIDC documentation: https://www.keycloak.org/securing-apps/oidc-layers
# spring-oidc
