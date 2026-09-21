# oidc-go-cli

Authorization Code + PKCE (browser + loopback redirect) **or** Device flow, ID-token verification
with go-oidc, then **group-based access control**.

```bash
go mod tidy                                                     # fetches go-oidc + x/oauth2
go run . --issuer http://localhost:8080/realms/demo --client-id cli-go --require-group /developers
go run . --issuer ... --flow device                             # no browser on this machine (e.g. over SSH)
go build -o oidc-go-cli . && ./oidc-go-cli --issuer ... --require-group /admins,/developers --any-group
```

See `docs/11-oidc-cli-clients-java-go.md`.
