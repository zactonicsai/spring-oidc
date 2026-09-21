# oidc-java-cli

Device-flow login against Keycloak, JWT verification via JWKS, then **group-based access control**.

```bash
mvn -q package                                          # needs Maven + JDK 21+ (the devbox has both)
java -jar target/oidc-cli.jar --issuer http://localhost:8080/realms/demo --client-id cli-java --require-group /developers
# alice (developers) -> ALLOWED · bob (customers) -> DENIED (exit 2) · carol (developers+admins) -> ALLOWED
java -jar target/oidc-cli.jar --issuer ... --require-group /admins,/developers          # must be in ALL
java -jar target/oidc-cli.jar --issuer ... --require-group /admins,/developers --any-group   # ANY of them
```

See `docs/11-oidc-cli-clients-java-go.md`.
