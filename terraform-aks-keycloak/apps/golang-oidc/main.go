package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

var (
	issuer       = env("OIDC_ISSUER", "http://keycloak.identity.svc.cluster.local:8080/realms/demo")
	clientID     = env("OIDC_CLIENT_ID", "golang-oidc")
	clientSecret = env("OIDC_CLIENT_SECRET", "")
	port         = env("PORT", "8080")
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", index)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]any{"status": "ok", "app": "golang-oidc"})
	})
	mux.HandleFunc("/public", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]any{"message": "public golang endpoint"})
	})
	mux.HandleFunc("/protected", protected)
	mux.HandleFunc("/client-credentials", clientCredentials)
	log.Printf("golang-oidc listening on %s issuer=%s", port, issuer)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func index(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintf(w, `<html><body style="font-family:sans-serif">
<h1>Golang OIDC example</h1>
<p>Issuer: %s</p>
<p>Client: %s</p>
<ul>
<li><a href="/health">/health</a></li>
<li><a href="/public">/public</a></li>
<li>/protected (send Authorization: Bearer &lt;access_token&gt;)</li>
<li>/client-credentials (uses confidential client secret)</li>
</ul>
</body></html>`, issuer, clientID)
}

func protected(w http.ResponseWriter, r *http.Request) {
	token := bearer(r)
	if token == "" {
		writeJSON(w, 401, map[string]any{"error": "missing_bearer_token"})
		return
	}
	payload, err := decodeJWTPayload(token)
	if err != nil {
		writeJSON(w, 401, map[string]any{"error": "invalid_token", "detail": err.Error()})
		return
	}
	if iss, _ := payload["iss"].(string); iss != issuer {
		writeJSON(w, 401, map[string]any{"error": "invalid_issuer", "expected": issuer, "got": iss})
		return
	}
	if exp, ok := payload["exp"].(float64); ok && int64(exp) < time.Now().Unix() {
		writeJSON(w, 401, map[string]any{"error": "token_expired"})
		return
	}
	ui := userinfo(token)
	writeJSON(w, 200, map[string]any{"app": "golang-oidc", "claims": payload, "userinfo": ui})
}

func clientCredentials(w http.ResponseWriter, r *http.Request) {
	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("client_id", clientID)
	form.Set("client_secret", clientSecret)
	resp, err := http.Post(issuer+"/protocol/openid-connect/token", "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if err != nil {
		writeJSON(w, 500, map[string]any{"error": err.Error()})
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	writeJSON(w, resp.StatusCode, map[string]any{"token_endpoint_status": resp.StatusCode, "raw": string(body)})
}

func userinfo(token string) map[string]any {
	req, _ := http.NewRequest(http.MethodGet, issuer+"/protocol/openid-connect/userinfo", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return map[string]any{"error": err.Error()}
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return map[string]any{"status": resp.StatusCode, "body": string(body)}
}

func decodeJWTPayload(jwt string) (map[string]any, error) {
	parts := strings.Split(jwt, ".")
	if len(parts) < 2 {
		return nil, fmt.Errorf("not a JWT")
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		b, err2 := base64.URLEncoding.DecodeString(pad(parts[1]))
		if err2 != nil {
			return nil, err
		}
		raw = b
	}
	out := map[string]any{}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func pad(s string) string {
	for len(s)%4 != 0 {
		s += "="
	}
	return s
}

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if strings.HasPrefix(h, "Bearer ") {
		return strings.TrimPrefix(h, "Bearer ")
	}
	return ""
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}
