// oidc-go-cli — log in to Keycloak from the command line and enforce group-based access control.
//
// Two flows, both made for CLIs:
//
//	--flow code    Authorization Code + PKCE: opens the browser, Keycloak redirects to a loopback
//	               port (http://localhost:8765/callback) where this program receives the code.
//	--flow device  Device Authorization Grant (RFC 8628): prints a URL + code; works over SSH.
//
// The ID token is verified with the issuer's JWKS (go-oidc), then the "groups" claim decides:
//
//	go run . --issuer http://localhost:8080/realms/demo --client-id cli-go --require-group /developers
//
// Exit codes: 0 authorized · 2 authenticated but not in the required group(s) · 1 error.
package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"
)

type claims struct {
	Subject           string   `json:"sub"`
	PreferredUsername string   `json:"preferred_username"`
	Email             string   `json:"email"`
	Groups            []string `json:"groups"`
	AuthorizedParty   string   `json:"azp"`
}

func main() {
	issuer := flag.String("issuer", "", "OIDC issuer, e.g. http://localhost:8080/realms/demo")
	clientID := flag.String("client-id", "cli-go", "public client id registered in the realm")
	flow := flag.String("flow", "code", "code (browser + loopback redirect) or device (print a code)")
	callback := flag.String("callback", "http://localhost:8765/callback", "loopback redirect URI registered on the client")
	requireGroups := flag.String("require-group", "/developers", "comma-separated group paths the user must belong to")
	anyGroup := flag.Bool("any-group", false, "allow if the user is in ANY of the groups (default: ALL)")
	action := flag.String("action", "deploy", "name of the protected action (for the message)")
	flag.Parse()
	if *issuer == "" {
		flag.Usage()
		os.Exit(1)
	}
	*issuer = strings.TrimSuffix(*issuer, "/")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	// 1. Discovery: endpoints + JWKS from /.well-known/openid-configuration
	provider, err := oidc.NewProvider(ctx, *issuer)
	fatal(err, "discovery")

	conf := &oauth2.Config{
		ClientID:    *clientID,
		Endpoint:    provider.Endpoint(), // has AuthURL, TokenURL and DeviceAuthURL
		RedirectURL: *callback,
		Scopes:      []string{oidc.ScopeOpenID, "profile", "email"},
	}

	// 2. Get tokens with the chosen flow
	var token *oauth2.Token
	switch *flow {
	case "code":
		token, err = loginWithCode(ctx, conf)
	case "device":
		token, err = loginWithDevice(ctx, conf)
	default:
		err = fmt.Errorf("unknown --flow %q", *flow)
	}
	fatal(err, "login")

	// 3. VERIFY the ID token: signature (JWKS), issuer, audience (= our client id), expiry
	rawID, ok := token.Extra("id_token").(string)
	if !ok || rawID == "" {
		fatal(errors.New("no id_token in the response (is the openid scope enabled?)"), "token")
	}
	verifier := provider.Verifier(&oidc.Config{ClientID: *clientID})
	idToken, err := verifier.Verify(ctx, rawID)
	fatal(err, "verify id_token")
	var c claims
	fatal(idToken.Claims(&c), "claims")

	// 4. Group-based access control
	fmt.Printf("==> authenticated as %s (%s)\n    groups: %v   expires: %s\n", c.PreferredUsername, c.Email, c.Groups, idToken.Expiry.Format(time.RFC3339))
	required := strings.Split(*requireGroups, ",")
	if !authorized(c.Groups, required, *anyGroup) {
		mode := "all"
		if *anyGroup {
			mode = "any"
		}
		fmt.Printf("✖ DENIED: action %q requires %s of %v; you are in %v\n", *action, mode, required, c.Groups)
		os.Exit(2)
	}
	fmt.Printf("✔ ALLOWED: %q may run %q (member of %v)\n", c.PreferredUsername, *action, required)
	// ... a real CLI now calls its API with  Authorization: Bearer <token.AccessToken>
	// and refreshes with conf.TokenSource(ctx, token) when it expires.
}

// loginWithCode runs Authorization Code + PKCE with a loopback redirect (RFC 8252 style).
func loginWithCode(ctx context.Context, conf *oauth2.Config) (*oauth2.Token, error) {
	state := randomString(24)
	verifier := oauth2.GenerateVerifier() // PKCE: proves the same program that started the login finishes it
	authURL := conf.AuthCodeURL(state, oauth2.AccessTypeOffline, oauth2.S256ChallengeOption(verifier))

	// listen on the loopback port named in the redirect URI
	addr := strings.TrimPrefix(strings.TrimPrefix(conf.RedirectURL, "http://"), "https://")
	host := addr[:strings.Index(addr, "/")]
	path := addr[strings.Index(addr, "/"):]
	ln, err := net.Listen("tcp", host)
	if err != nil {
		return nil, fmt.Errorf("listen on %s (is the port free?): %w", host, err)
	}
	codeCh := make(chan string, 1)
	errCh := make(chan error, 1)
	srv := &http.Server{ReadHeaderTimeout: 10 * time.Second}
	http.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		if q.Get("state") != state { // CSRF check
			http.Error(w, "state mismatch", http.StatusBadRequest)
			errCh <- errors.New("state mismatch")
			return
		}
		if e := q.Get("error"); e != "" {
			http.Error(w, e+": "+q.Get("error_description"), http.StatusBadRequest)
			errCh <- errors.New(e + ": " + q.Get("error_description"))
			return
		}
		fmt.Fprintln(w, "Login complete - you can close this tab and return to the terminal.")
		codeCh <- q.Get("code")
	})
	go func() { _ = srv.Serve(ln) }()
	defer func() { _ = srv.Shutdown(context.Background()) }()

	fmt.Println("==> Opening the browser for login (or open this URL yourself):")
	fmt.Println("    " + authURL)
	openBrowser(authURL)

	select {
	case code := <-codeCh:
		return conf.Exchange(ctx, code, oauth2.VerifierOption(verifier)) // send the PKCE verifier
	case err := <-errCh:
		return nil, err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

// loginWithDevice runs the Device Authorization Grant — no browser needed on this machine.
func loginWithDevice(ctx context.Context, conf *oauth2.Config) (*oauth2.Token, error) {
	da, err := conf.DeviceAuth(ctx)
	if err != nil {
		return nil, fmt.Errorf("device authorization request: %w", err)
	}
	url := da.VerificationURIComplete
	if url == "" {
		url = da.VerificationURI
	}
	fmt.Printf("==> Open %s and confirm code %s (waiting ...)\n", url, da.UserCode)
	return conf.DeviceAccessToken(ctx, da) // polls the token endpoint, honours interval/slow_down
}

func authorized(have, required []string, anyOf bool) bool {
	set := map[string]bool{}
	for _, g := range have {
		set[strings.TrimSpace(g)] = true
	}
	matches := 0
	for _, r := range required {
		if set[strings.TrimSpace(r)] {
			matches++
		}
	}
	if anyOf {
		return matches > 0
	}
	return matches == len(required)
}

func randomString(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	_ = cmd.Start() // best effort; the URL was printed anyway (over SSH use --flow device)
}

func fatal(err error, what string) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "error (%s): %v\n", what, err)
		os.Exit(1)
	}
}
