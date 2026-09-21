package demo;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.jwk.source.JWKSourceBuilder;
import com.nimbusds.jose.proc.JWSVerificationKeySelector;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jose.util.JSONObjectUtils;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.proc.DefaultJWTClaimsVerifier;
import com.nimbusds.jwt.proc.DefaultJWTProcessor;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * A command-line client that logs a user in with the OAuth 2.0 Device Authorization Grant
 * (RFC 8628 — the flow made for CLIs and devices without a browser), verifies the returned
 * access token against the issuer's JWKS, and then enforces GROUP-BASED ACCESS CONTROL:
 * the user must be a member of every group given with --require-group.
 *
 *   java -jar target/oidc-cli.jar --issuer http://localhost:8080/realms/demo --client-id cli-java \
 *        --require-group /developers [--action deploy] [--any-group]
 *
 * Exit codes: 0 authorized · 2 authenticated but not in the required group(s) · 1 error.
 */
public final class OidcCli {

    private static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    public static void main(String[] args) throws Exception {
        Map<String, String> opt = parseArgs(args);
        String issuer = require(opt, "issuer");                 // e.g. http://localhost:8080/realms/demo
        String clientId = opt.getOrDefault("client-id", "cli-java");
        List<String> requiredGroups = opt.containsKey("require-group")
                ? List.of(opt.get("require-group").split(","))
                : List.of("/developers");
        boolean anyGroup = opt.containsKey("any-group");
        String action = opt.getOrDefault("action", "deploy");

        // 1. OIDC discovery: one document tells us every endpoint + the JWKS location.
        Map<String, Object> discovery = getJson(issuer + "/.well-known/openid-configuration");
        String deviceEndpoint = JSONObjectUtils.getString(discovery, "device_authorization_endpoint");
        String tokenEndpoint = JSONObjectUtils.getString(discovery, "token_endpoint");
        String jwksUri = JSONObjectUtils.getString(discovery, "jwks_uri");
        if (deviceEndpoint == null) {
            throw new IllegalStateException("issuer does not advertise the device authorization grant");
        }

        // 2. Device authorization request: we get a short user code and a URL to show the human.
        Map<String, Object> device = postForm(deviceEndpoint, Map.of(
                "client_id", clientId,
                "scope", "openid profile email"));
        String deviceCode = JSONObjectUtils.getString(device, "device_code");
        String userCode = JSONObjectUtils.getString(device, "user_code");
        String verifyUrl = device.containsKey("verification_uri_complete")
                ? JSONObjectUtils.getString(device, "verification_uri_complete")
                : JSONObjectUtils.getString(device, "verification_uri");
        long interval = device.containsKey("interval") ? JSONObjectUtils.getLong(device, "interval") : 5L;
        long expiresIn = device.containsKey("expires_in") ? JSONObjectUtils.getLong(device, "expires_in") : 600L;

        System.out.println("==> Open this URL in a browser and confirm the code " + userCode + ":");
        System.out.println("    " + verifyUrl);
        System.out.println("    (waiting up to " + expiresIn + " s, polling every " + interval + " s)");

        // 3. Poll the token endpoint until the human approved (or the code expired).
        Map<String, Object> tokens = null;
        long deadline = System.currentTimeMillis() + expiresIn * 1000;
        while (System.currentTimeMillis() < deadline) {
            Thread.sleep(interval * 1000);
            Map<String, Object> resp = postForm(tokenEndpoint, Map.of(
                    "grant_type", "urn:ietf:params:oauth:grant-type:device_code",
                    "device_code", deviceCode,
                    "client_id", clientId));
            if (resp.containsKey("access_token")) {
                tokens = resp;
                break;
            }
            String err = String.valueOf(resp.get("error"));
            switch (err) {
                case "authorization_pending" -> System.out.print(".");
                case "slow_down" -> interval += 5;                        // RFC 8628 §3.5: back off
                default -> throw new IllegalStateException("login failed: " + err + " " + resp.get("error_description"));
            }
        }
        System.out.println();
        if (tokens == null) {
            throw new IllegalStateException("the user code expired before it was confirmed");
        }
        String accessToken = JSONObjectUtils.getString(tokens, "access_token");

        // 4. VERIFY the token — never trust claims from an unverified JWT.
        //    signature (RS256, key from the issuer's JWKS, cached + auto-refreshed), issuer, exp/iat, required claims.
        JWKSource<SecurityContext> jwks = JWKSourceBuilder.create(URI.create(jwksUri).toURL()).build();
        DefaultJWTProcessor<SecurityContext> processor = new DefaultJWTProcessor<>();
        processor.setJWSKeySelector(new JWSVerificationKeySelector<>(JWSAlgorithm.RS256, jwks));
        processor.setJWTClaimsSetVerifier(new DefaultJWTClaimsVerifier<>(
                new JWTClaimsSet.Builder().issuer(issuer).build(),        // exact-match claims
                Set.of("sub", "iat", "exp", "azp")));                      // must be present
        JWTClaimsSet claims = processor.process(accessToken, null);
        if (!clientId.equals(claims.getStringClaim("azp"))) {              // token was issued to THIS client
            throw new IllegalStateException("token azp=" + claims.getStringClaim("azp") + " is not " + clientId);
        }

        // 5. Group-based access control. The realm's "groups" mapper puts group paths in the token.
        List<String> groups = claims.getStringListClaim("groups");
        if (groups == null) {
            groups = new ArrayList<>();
        }
        String user = claims.getStringClaim("preferred_username");
        System.out.println("==> authenticated as " + user + " (" + claims.getStringClaim("email") + ")");
        System.out.println("    groups: " + groups + "   token expires: " + claims.getExpirationTime());

        boolean allowed = anyGroup
                ? requiredGroups.stream().anyMatch(groups::contains)
                : groups.containsAll(requiredGroups);
        if (!allowed) {
            System.out.println("✖ DENIED: action '" + action + "' requires group(s) " + requiredGroups
                    + (anyGroup ? " (any)" : " (all)") + "; you are in " + groups);
            System.exit(2);
        }
        System.out.println("✔ ALLOWED: '" + user + "' may run '" + action + "' (member of " + requiredGroups + ")");
        // ... here the real CLI would call a protected API with:  Authorization: Bearer <accessToken>
    }

    // ------------------------------------------------------------------ helpers -----
    private static Map<String, Object> getJson(String url) throws Exception {
        HttpResponse<String> r = HTTP.send(HttpRequest.newBuilder(URI.create(url)).GET().build(),
                HttpResponse.BodyHandlers.ofString());
        if (r.statusCode() != 200) {
            throw new IllegalStateException("GET " + url + " -> " + r.statusCode());
        }
        return JSONObjectUtils.parse(r.body());
    }

    private static Map<String, Object> postForm(String url, Map<String, String> form) throws Exception {
        StringBuilder body = new StringBuilder();
        for (Map.Entry<String, String> e : form.entrySet()) {
            if (body.length() > 0) {
                body.append('&');
            }
            body.append(URLEncoder.encode(e.getKey(), StandardCharsets.UTF_8)).append('=')
                .append(URLEncoder.encode(e.getValue(), StandardCharsets.UTF_8));
        }
        HttpRequest req = HttpRequest.newBuilder(URI.create(url))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(body.toString())).build();
        HttpResponse<String> r = HTTP.send(req, HttpResponse.BodyHandlers.ofString());
        return JSONObjectUtils.parse(r.body());                            // OAuth errors come back as JSON too
    }

    private static Map<String, String> parseArgs(String[] args) {
        Map<String, String> m = new HashMap<>();
        for (int i = 0; i < args.length; i++) {
            if (args[i].startsWith("--")) {
                String key = args[i].substring(2);
                boolean hasValue = i + 1 < args.length && !args[i + 1].startsWith("--");
                m.put(key, hasValue ? args[++i] : "");
            }
        }
        return m;
    }

    private static String require(Map<String, String> m, String key) {
        String v = m.get(key);
        if (v == null || v.isBlank()) {
            System.err.println("usage: --issuer <url> [--client-id cli-java] [--require-group /developers[,/admins]] [--any-group] [--action name]");
            System.exit(1);
        }
        return v.endsWith("/") ? v.substring(0, v.length() - 1) : v;
    }
}
