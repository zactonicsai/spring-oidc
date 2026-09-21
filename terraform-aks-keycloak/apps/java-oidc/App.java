import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

/**
 * Minimal Java 27 OIDC resource-server example.
 * Validates bearer tokens by checking issuer/expiry locally and calling Keycloak userinfo.
 */
public class App {
    static final String ISSUER = env("OIDC_ISSUER", "http://keycloak.identity.svc.cluster.local:8080/realms/demo");
    static final String CLIENT_ID = env("OIDC_CLIENT_ID", "java-oidc");
    static final String CLIENT_SECRET = env("OIDC_CLIENT_SECRET", "");
    static final int PORT = Integer.parseInt(env("PORT", "8080"));
    static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    public static void main(String[] args) throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress(PORT), 0);
        server.createContext("/", App::index);
        server.createContext("/health", ex -> json(ex, 200, Map.of("status", "ok", "app", "java-oidc")));
        server.createContext("/public", ex -> json(ex, 200, Map.of("message", "public java endpoint")));
        server.createContext("/protected", App::protectedApi);
        server.createContext("/client-credentials", App::clientCredentials);
        server.start();
        System.out.println("java-oidc listening on " + PORT + " issuer=" + ISSUER);
    }

    static void index(HttpExchange ex) throws IOException {
        String html = """
            <html><body style="font-family:sans-serif">
              <h1>Java OIDC example</h1>
              <p>Issuer: %s</p>
              <p>Client: %s</p>
              <ul>
                <li><a href="/health">/health</a></li>
                <li><a href="/public">/public</a></li>
                <li>/protected (send Authorization: Bearer &lt;access_token&gt;)</li>
                <li>/client-credentials (uses confidential client secret)</li>
              </ul>
            </body></html>
            """.formatted(ISSUER, CLIENT_ID);
        html(ex, 200, html);
    }

    static void protectedApi(HttpExchange ex) throws IOException {
        Optional<String> token = bearer(ex);
        if (token.isEmpty()) {
            json(ex, 401, Map.of("error", "missing_bearer_token"));
            return;
        }
        try {
            Map<String, Object> claims = decodeJwtPayload(token.get());
            Object iss = claims.get("iss");
            Object exp = claims.get("exp");
            if (iss == null || !ISSUER.equals(String.valueOf(iss))) {
                json(ex, 401, Map.of("error", "invalid_issuer", "expected", ISSUER, "got", String.valueOf(iss)));
                return;
            }
            if (exp instanceof Number n && n.longValue() < System.currentTimeMillis() / 1000) {
                json(ex, 401, Map.of("error", "token_expired"));
                return;
            }
            Map<String, Object> userinfo = userinfo(token.get());
            json(ex, 200, Map.of(
                    "app", "java-oidc",
                    "claims", claims,
                    "userinfo", userinfo
            ));
        } catch (Exception e) {
            json(ex, 401, Map.of("error", "invalid_token", "detail", e.getMessage()));
        }
    }

    static void clientCredentials(HttpExchange ex) throws IOException {
        try {
            String body = "grant_type=client_credentials&client_id=" + CLIENT_ID + "&client_secret=" + CLIENT_SECRET;
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(ISSUER + "/protocol/openid-connect/token"))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> res = HTTP.send(req, HttpResponse.BodyHandlers.ofString());
            json(ex, res.statusCode(), Map.of("token_endpoint_status", res.statusCode(), "raw", res.body()));
        } catch (Exception e) {
            json(ex, 500, Map.of("error", e.getMessage()));
        }
    }

    static Map<String, Object> userinfo(String token) throws Exception {
        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(ISSUER + "/protocol/openid-connect/userinfo"))
                .header("Authorization", "Bearer " + token)
                .GET()
                .build();
        HttpResponse<String> res = HTTP.send(req, HttpResponse.BodyHandlers.ofString());
        return Map.of("status", res.statusCode(), "body", res.body());
    }

    static Map<String, Object> decodeJwtPayload(String jwt) {
        String[] parts = jwt.split("\\.");
        if (parts.length < 2) throw new IllegalArgumentException("not a JWT");
        String json = new String(Base64.getUrlDecoder().decode(pad(parts[1])), StandardCharsets.UTF_8);
        return Map.of("raw_payload", json);
    }

    static String pad(String s) {
        return s + "=".repeat((4 - s.length() % 4) % 4);
    }

    static Optional<String> bearer(HttpExchange ex) {
        String h = ex.getRequestHeaders().getFirst("Authorization");
        if (h != null && h.startsWith("Bearer ")) return Optional.of(h.substring(7));
        return Optional.empty();
    }

    static void json(HttpExchange ex, int status, Map<String, ?> body) throws IOException {
        byte[] bytes = pretty(body).getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().set("Content-Type", "application/json");
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = ex.getResponseBody()) { os.write(bytes); }
    }

    static void html(HttpExchange ex, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = ex.getResponseBody()) { os.write(bytes); }
    }

    static String pretty(Map<String, ?> map) {
        StringBuilder sb = new StringBuilder("{\n");
        boolean first = true;
        for (var e : new LinkedHashMap<>(map).entrySet()) {
            if (!first) sb.append(",\n");
            first = false;
            sb.append("  \"").append(e.getKey()).append("\": ");
            Object v = e.getValue();
            if (v instanceof Number || v instanceof Boolean) sb.append(v);
            else sb.append("\"").append(String.valueOf(v).replace("\"", "\\\"")).append("\"");
        }
        return sb.append("\n}\n").toString();
    }

    static String env(String k, String d) {
        String v = System.getenv(k);
        return v == null || v.isBlank() ? d : v;
    }
}
