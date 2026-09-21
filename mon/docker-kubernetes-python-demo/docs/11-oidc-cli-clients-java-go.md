# OIDC Command-Line Clients: Java and Go, with Group-Based Access Control

*Two small programs that log a user in against the Keycloak realm from tutorial 09 and then
decide what the user may do based on the **groups** they belong to. The Java CLI uses the
**Device Authorization Grant** (made for terminals); the Go CLI uses **Authorization Code + PKCE
with a loopback redirect** (made for desktop tools) and can also do the device flow. Both verify
the token cryptographically before trusting a single claim. Current as of September 2026
(Keycloak 26.7, Nimbus JOSE+JWT 10, go-oidc v3, x/oauth2).*

| Part | What you learn |
|---|---|
| [1](#part-1--step-by-step) | Import the demo realm, run both clients, see ALLOWED vs DENIED |
| [2](#part-2--the-ideas) | OIDC vs OAuth, issuer/discovery/JWKS, the two CLI flows, tokens, groups vs roles |
| [3](#part-3--the-realm) | What `realm-demo.json` sets up and why |
| [4](#part-4--the-java-client-line-by-line) | Device flow, JWKS verification, `azp`, the group check |
| [5](#part-5--the-go-client-line-by-line) | PKCE, loopback listener, state, ID-token verification, device mode |
| [6](#part-6--best-practices) | Verify everything, public clients, short tokens, group design, least privilege |
| [7](#part-7--gotchas) | The errors you will actually hit |
| [8](#part-8--pros-and-cons) | Device flow vs code+PKCE vs client credentials; groups vs roles vs scopes |

---

## Part 1 — Step by step

```bash
# 0. Keycloak up (tutorial 09) — the demo realm is imported at first start
./scripts/keycloak.sh deploy && ./scripts/keycloak.sh open        # kind: http://localhost:8080
./scripts/keycloak.sh realm                                         # (re)apply k8s/keycloak/realm-demo.json on a running server

# realm "demo": groups /developers /admins /customers
#   alice / alice  -> /developers            bob / bob -> /customers            carol / carol -> /developers + /admins
# clients: cli-java (device grant), cli-go (code+PKCE on http://localhost:8765/callback, and device grant)

# 1. Java — device flow
cd examples/oidc-java-cli && mvn -q package
java -jar target/oidc-cli.jar --issuer http://localhost:8080/realms/demo --client-id cli-java --require-group /developers
#   ==> Open this URL in a browser and confirm the code ABCD-EFGH:  http://localhost:8080/realms/demo/device?user_code=...
#   log in as alice  -> ✔ ALLOWED    log in as bob -> ✖ DENIED (exit code 2)

# 2. Go — authorization code + PKCE (opens your browser) …
cd ../oidc-go-cli && go mod tidy
go run . --issuer http://localhost:8080/realms/demo --client-id cli-go --require-group /developers
# … or device flow, e.g. inside the devbox over SSH
go run . --issuer http://keycloak.keycloak/realms/demo --client-id cli-go --flow device --require-group /admins,/developers --any-group
```

Both print the verified identity, its groups, the token expiry and the decision, and exit
`0` (allowed), `2` (authenticated but not authorized) or `1` (error) — so shell scripts and CI can
branch on it.

> On AKS replace `http://localhost:8080` with `http://<keycloak public IP>` (or the HTTPS hostname
> once you have an Ingress). The issuer string must be *exactly* what Keycloak believes it is —
> see gotchas.

---

## Part 2 — The ideas

| Term | Grocery-store version | Precisely |
|---|---|---|
| **OAuth 2.0** | a *permission slip*: "the holder may take one cart" | delegated authorization — an access token lets a client call an API |
| **OIDC** (OpenID Connect) | the *staff badge with a photo*: who you are | identity layer on OAuth: adds the **ID token** and user info |
| **Issuer** | the badge office | the URL that identifies the authority, e.g. `…/realms/demo`; every token says `iss` |
| **Discovery** | the sign in the lobby listing every counter | `/.well-known/openid-configuration` → endpoints, JWKS URL, supported flows |
| **JWKS** | the office's list of official stamps | public keys used to check token signatures; rotated, so fetch by `kid` and cache |
| **Client** | a program registered with the office | `cli-java`, `cli-go`; **public** clients (no secret — anything a user can download) vs **confidential** (servers) |
| **Access token** | the permission slip | short-lived JWT (5 min here) sent as `Authorization: Bearer` to APIs |
| **ID token** | the badge | JWT *about the user* for the client itself; audience = the client |
| **Refresh token** | "come back for a new slip without queueing" | long-lived, gets new access tokens |
| **Claims** | the fields printed on the badge | `sub`, `preferred_username`, `email`, `groups`, `azp`, `exp` … |
| **Groups** | departments a person belongs to | Keycloak groups (hierarchical paths like `/developers`), put into tokens by a *mapper* |
| **Roles** | job titles | realm/client roles; also mappable; groups can *carry* roles |

### The two CLI flows

```
DEVICE AUTHORIZATION GRANT (RFC 8628)                AUTHORIZATION CODE + PKCE (RFC 6749 + 7636)
cli ──POST device_authorization──► Keycloak          cli starts a listener on http://localhost:8765/callback
cli ◄── user_code + verification_uri ──              cli opens browser: authorize?code_challenge=SHA256(verifier)&state=…
user opens the URL on ANY device, logs in            user logs in; Keycloak redirects browser → localhost:8765/callback?code=…&state=…
cli polls token endpoint (interval, slow_down)       cli checks state, POSTs code + code_verifier to the token endpoint
cli ◄── tokens ──                                    cli ◄── tokens ──
best for: terminals, SSH sessions, TVs, CI boxes     best for: desktop tools with a browser on the same machine
```

Neither flow ever sees the user's password. Never use the "password grant" (Resource Owner
Password Credentials) — it is removed in OAuth 2.1 and disabled on these clients.

---

## Part 3 — The realm

`k8s/keycloak/realm-demo.json` is imported by `--import-realm` on the first start (mounted from
a ConfigMap) and can be re-applied with `keycloak.sh realm` (`kcadm.sh partialImport … OVERWRITE`).

| Item | Setting | Why |
|---|---|---|
| realm `demo` | `bruteForceProtected: true`, access token 300 s, `sslRequired: external` | sane defaults; HTTP allowed only for private addresses |
| groups | `/developers`, `/admins`, `/customers` | the access-control dimension the CLIs check |
| users | alice, bob, carol with passwords = usernames | demo only |
| client `cli-java` | public, `oauth2.device.authorization.grant.enabled=true`, standard flow **off** | a device-flow-only client can't be tricked into redirect attacks |
| client `cli-go` | public, standard flow with `pkce.code.challenge.method=S256`, redirect URIs `http://localhost:8765/callback` + `127.0.0.1`, device grant on | exact loopback redirect; PKCE enforced by the server |
| protocol mapper `groups` on both | `oidc-group-membership-mapper`, `full.path=true`, in access + ID + userinfo | tokens carry `"groups": ["/developers"]` |

Change anything in the Admin Console (`/admin`, realm *demo*) — but put it back into the JSON so
it is reproducible.

---

## Part 4 — The Java client, line by line

`examples/oidc-java-cli/src/main/java/demo/OidcCli.java` (JDK 21+, one dependency:
`com.nimbusds:nimbus-jose-jwt`; built into a single jar by `maven-shade-plugin`).

1. **Discovery** — `GET <issuer>/.well-known/openid-configuration`, read
   `device_authorization_endpoint`, `token_endpoint`, `jwks_uri`. Never hard-code endpoints.
2. **Device authorization** — `POST device_authorization_endpoint` with `client_id` and
   `scope=openid profile email` → `device_code`, `user_code`, `verification_uri_complete`,
   `interval`, `expires_in`. Print the URL and code for the human.
3. **Polling** — every `interval` seconds `POST token_endpoint` with
   `grant_type=urn:ietf:params:oauth:grant-type:device_code`. Handle the three answers:
   `authorization_pending` (keep waiting), `slow_down` (add 5 s — required by the RFC),
   `access_denied`/`expired_token` (stop).
4. **Verification** — the part people skip and shouldn't:
   ```java
   JWKSource<SecurityContext> jwks = JWKSourceBuilder.create(URI.create(jwksUri).toURL()).build(); // cached, auto-refresh on unknown kid
   processor.setJWSKeySelector(new JWSVerificationKeySelector<>(JWSAlgorithm.RS256, jwks));       // only RS256, only keys from the issuer
   processor.setJWTClaimsSetVerifier(new DefaultJWTClaimsVerifier<>(
           new JWTClaimsSet.Builder().issuer(issuer).build(), Set.of("sub", "iat", "exp", "azp")));// iss must match; exp checked; these must exist
   JWTClaimsSet claims = processor.process(accessToken, null);
   if (!clientId.equals(claims.getStringClaim("azp"))) throw …;                                    // issued to THIS client
   ```
   `azp` (authorized party) is checked because Keycloak public clients don't put the client id in
   `aud` of the *access* token by default; the ID token's `aud` is the client id.
5. **Group check** — `claims.getStringListClaim("groups")`; require **all** groups from
   `--require-group a,b` or **any** with `--any-group`; exit 2 when denied. The real CLI would
   then call its API with `Authorization: Bearer …` and let the API re-check the same claims.

---

## Part 5 — The Go client, line by line

`examples/oidc-go-cli/main.go` (Go 1.24+, `github.com/coreos/go-oidc/v3` and `golang.org/x/oauth2`;
`go mod tidy` pins them).

1. `oidc.NewProvider(ctx, issuer)` does discovery and remembers the JWKS URL.
2. `oauth2.Config{ClientID, Endpoint: provider.Endpoint(), RedirectURL, Scopes}` — `Endpoint()`
   includes the device-authorization URL, so the same config serves both flows.
3. **Code flow**: `oauth2.GenerateVerifier()` + `S256ChallengeOption` create the PKCE pair; a random
   `state` defeats CSRF; a tiny `net/http` server on the loopback port receives `code` and `state`
   (checked!) and hands the code to `conf.Exchange(ctx, code, oauth2.VerifierOption(verifier))`.
   The browser is opened with `xdg-open`/`open`; the URL is printed too (useful over SSH — or use
   `--flow device`).
4. **Device flow**: `conf.DeviceAuth(ctx)` then `conf.DeviceAccessToken(ctx, da)` — the library polls
   and honours `interval`/`slow_down`.
5. **Verification**: `provider.Verifier(&oidc.Config{ClientID: clientID}).Verify(ctx, rawIDToken)`
   checks signature (JWKS), `iss`, `aud == client id`, `exp`; then `idToken.Claims(&c)` unmarshals
   `groups`, `preferred_username`, `email`.
6. **Group check** — identical semantics to the Java client (`--require-group`, `--any-group`),
   exit code 2 on denial. For long-running tools keep `conf.TokenSource(ctx, token)` — it refreshes
   automatically.

---

## Part 6 — Best practices

* **Verify before you trust**: signature against the issuer's JWKS, `iss`, `exp`, and *audience*
  (`aud` for ID tokens, `azp` for Keycloak access tokens). Pin the algorithm (`RS256`, or ES256 if
  you configure it) — never accept `none`.
* **Public clients have no secret** — anything shipped to users is public. Use PKCE (`S256`,
  enforced server-side) and exact loopback redirect URIs; enable the device grant only on clients
  that need it.
* **Short access tokens (5 min), refresh tokens with rotation** (Keycloak: *Revoke Refresh Token*
  on, *Refresh Token Max Reuse* 0). Store refresh tokens in the OS keychain, never in plain files.
* **Authorize on the server, too.** The CLI's group check is UX; the API it calls must repeat the
  same check on the same token. Keycloak's *Authorization Services* or a policy engine (OPA, Cedar)
  scale this beyond "is in group X".
* **Groups for organisation, roles for permissions.** Keep groups few and stable
  (`/developers`, `/platform/oncall`); attach *roles* to groups and check roles in fine-grained
  code paths. Use `full.path=true` so `/sales/admins` and `/it/admins` don't collide.
* **Least privilege in the token**: only map the claims a client needs (a `groups` mapper on a
  client scope shared by CLI clients, not on every client); big tokens leak information and hit
  header limits.
* **Log decisions, not tokens.** Print `sub`/username and the outcome; never log the JWT.
* **Automate the realm**: keep `realm-demo.json` in git, apply it in CI (`kcadm.sh`/Terraform
  `keycloak` provider), disable the bootstrap admin after creating real admins, use HTTPS +
  `KC_HOSTNAME_STRICT=true` outside demos.
* **Rate limits and brute force**: leave `bruteForceProtected` on; the monitoring alert
  `KeycloakHighLoginFailureRate` (tutorial 12) tells you when someone is guessing passwords.

---

## Part 7 — Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `issuer did not match the issuer returned by provider` / *Invalid issuer* | you used `localhost:8080` but tokens say `http://<lb-ip>/realms/demo` (or vice versa) | the issuer URL you configure must equal what Keycloak puts in `iss`; set `KC_HOSTNAME` for a fixed one |
| Java: `device_authorization_endpoint` missing | device grant disabled on the client/realm | `oauth2.device.authorization.grant.enabled=true` (already in the JSON) |
| `unauthorized_client` at the token endpoint | wrong `client_id`, or standard flow disabled for the flow you chose | `cli-java` = device only; `cli-go` = code + device |
| Go: `invalid redirect_uri` | the loopback URI isn't registered exactly | `redirectUris` must match `http://localhost:8765/callback` exactly (scheme, host, port, path) |
| Go: `listen tcp 127.0.0.1:8765: address already in use` | previous run still holds the port | `--callback http://localhost:8766/callback` + register it |
| `groups` claim missing → always DENIED | mapper not on this client, or wrong scope | the JSON adds a mapper per client; check *Client scopes → Evaluate* in the console |
| Java: `Signed JWT rejected: Another algorithm expected` | Keycloak realm uses ES256/RS512 | change `JWSAlgorithm.RS256` to the realm's algorithm |
| `slow_down` loop / `expired_token` | polling too fast / user took too long (10 min default) | respect `interval`; rerun |
| Works on the laptop, not in the devbox | browser flow can't open a browser over SSH | `--flow device` (Go) / the Java client is device-only |
| `PKIX path building failed` (Java) / `x509: certificate signed by unknown authority` (Go) | self-signed HTTPS in front of Keycloak | add the CA to the JVM truststore / system trust store; don't disable verification |
| Token accepted but 401 from your API | API checks `aud`, access token has only `azp` | add an *audience* mapper for the API's client id, or check `azp`; see Keycloak "audience support" |

---

## Part 8 — Pros and cons

### Which flow for a CLI

| | Device Authorization Grant | Authorization Code + PKCE (loopback) | Client Credentials |
|---|---|---|---|
| Needs a browser on the machine | no | yes | no |
| User present | yes | yes | **no** — it's for machines/service accounts |
| Phishing resistance | user verifies the code; can be phished if not careful | strong (redirect only to loopback) | n/a |
| UX | copy a code | one click | none |
| Use it for | SSH sessions, CI boxes, devices | desktop tools, IDE plugins | daemons, batch jobs, pipelines (confidential client + secret/cert) |

### How to model permissions

| | Groups (this tutorial) | Roles | Scopes / fine-grained policies |
|---|---|---|---|
| Represents | who you are in the org | what you may do | what this token may do / per-resource rules |
| Managed by | IdP admins, HR sync (LDAP/SCIM) | app owners | app owners / policy engine |
| Token size | small if few groups | small | grows with policies |
| Change without redeploy | yes | yes | depends |
| Best for | coarse gating ("developers may deploy") | per-feature checks | multi-tenant APIs, resource ownership |
