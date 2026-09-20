package com.example.oidccli.oidc;

import com.example.oidccli.config.OidcProperties;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtDecoders;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

@Service
public class OidcDeviceClient {

    private static final String DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code";

    private final OidcProperties properties;
    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;

    public OidcDeviceClient(OidcProperties properties, ObjectMapper objectMapper) {
        this.properties = properties;
        this.objectMapper = objectMapper;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
    }

    public OidcDiscovery discover() {
        properties.validate();

        URI discoveryUri = discoveryUri(properties.getIssuerUri());
        HttpRequest request = HttpRequest.newBuilder(discoveryUri)
                .GET()
                .timeout(Duration.ofSeconds(15))
                .header("Accept", "application/json")
                .build();

        HttpResponse<String> response = send(request);
        require2xx("OIDC discovery", response);

        OidcDiscovery discovery = read(response.body(), OidcDiscovery.class);
        verifyIssuer(discovery);

        if (isBlank(discovery.tokenEndpoint())) {
            throw new IllegalStateException("OIDC discovery document does not contain token_endpoint.");
        }
        if (isBlank(discovery.deviceAuthorizationEndpoint())) {
            throw new IllegalStateException(
                    "OIDC provider does not advertise device_authorization_endpoint. "
                            + "Enable Device Authorization Grant for the provider/client, or use a provider that supports RFC 8628.");
        }

        return discovery;
    }

    public DeviceAuthorizationResponse startDeviceAuthorization(OidcDiscovery discovery) {
        Map<String, String> form = new LinkedHashMap<>();
        addClientIdentity(form);
        form.put("scope", properties.getScope());
        addPostSecretIfNeeded(form);

        HttpRequest.Builder builder = formPost(URI.create(discovery.deviceAuthorizationEndpoint()), form);
        addBasicAuthIfNeeded(builder);

        HttpResponse<String> response = send(builder.build());
        require2xx("Device authorization", response);

        DeviceAuthorizationResponse device = read(response.body(), DeviceAuthorizationResponse.class);
        if (isBlank(device.deviceCode()) || isBlank(device.userCode()) || isBlank(device.verificationUri())) {
            throw new IllegalStateException("Device authorization response is missing required fields.");
        }
        return device;
    }

    public TokenResponse pollForTokens(OidcDiscovery discovery, DeviceAuthorizationResponse device) {
        long intervalSeconds = device.pollingIntervalSeconds();
        Instant providerDeadline = Instant.now().plusSeconds(Math.max(1L, device.expiresIn()));
        Instant configuredDeadline = Instant.now().plus(properties.getPollTimeout());
        Instant deadline = providerDeadline.isBefore(configuredDeadline) ? providerDeadline : configuredDeadline;

        while (Instant.now().isBefore(deadline)) {
            sleep(intervalSeconds);

            Map<String, String> form = new LinkedHashMap<>();
            form.put("grant_type", DEVICE_GRANT);
            form.put("device_code", device.deviceCode());
            addClientIdentity(form);
            addPostSecretIfNeeded(form);

            HttpRequest.Builder builder = formPost(URI.create(discovery.tokenEndpoint()), form);
            addBasicAuthIfNeeded(builder);

            HttpResponse<String> response;
            try {
                response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("Interrupted while waiting for OIDC authorization.", e);
            } catch (IOException e) {
                // RFC 8628 recommends reducing polling frequency after connection timeouts.
                intervalSeconds = Math.min(30L, Math.max(5L, intervalSeconds * 2L));
                continue;
            }

            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                return read(response.body(), TokenResponse.class);
            }

            JsonNode error = readTree(response.body());
            String errorCode = text(error, "error");

            if ("authorization_pending".equals(errorCode)) {
                continue;
            }
            if ("slow_down".equals(errorCode)) {
                intervalSeconds += 5L;
                continue;
            }
            if ("access_denied".equals(errorCode)) {
                throw new IllegalStateException("OIDC login was denied by the user or provider.");
            }
            if ("expired_token".equals(errorCode)) {
                throw new IllegalStateException("OIDC device code expired. Run login again.");
            }

            String description = text(error, "error_description");
            throw new IllegalStateException(
                    "Token endpoint returned HTTP " + response.statusCode()
                            + ": " + errorCode
                            + (description == null ? "" : " - " + description));
        }

        throw new IllegalStateException("Timed out waiting for OIDC login approval.");
    }

    public Jwt verifyIdToken(TokenResponse tokenResponse) {
        if (isBlank(tokenResponse.idToken())) {
            throw new IllegalStateException(
                    "No id_token was returned. Verify that the client is OIDC-enabled and OIDC_SCOPE includes 'openid'.");
        }

        JwtDecoder decoder = JwtDecoders.fromIssuerLocation(properties.getIssuerUri().toString());
        Jwt jwt = decoder.decode(tokenResponse.idToken());

        if (jwt.getAudience() == null || !jwt.getAudience().contains(properties.getClientId())) {
            throw new IllegalStateException(
                    "ID token audience does not contain expected client ID: " + properties.getClientId());
        }

        return jwt;
    }

    public JsonNode fetchUserInfo(OidcDiscovery discovery, TokenResponse tokenResponse) {
        if (isBlank(discovery.userinfoEndpoint()) || isBlank(tokenResponse.accessToken())) {
            return null;
        }

        HttpRequest request = HttpRequest.newBuilder(URI.create(discovery.userinfoEndpoint()))
                .GET()
                .timeout(Duration.ofSeconds(15))
                .header("Accept", "application/json")
                .header("Authorization", "Bearer " + tokenResponse.accessToken())
                .build();

        HttpResponse<String> response = send(request);
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            return null;
        }
        return readTree(response.body());
    }

    private URI discoveryUri(URI issuer) {
        String value = issuer.toString();
        while (value.endsWith("/")) {
            value = value.substring(0, value.length() - 1);
        }
        return URI.create(value + "/.well-known/openid-configuration");
    }

    private void verifyIssuer(OidcDiscovery discovery) {
        if (isBlank(discovery.issuer())) {
            throw new IllegalStateException("OIDC discovery document does not contain issuer.");
        }
        String configured = stripTrailingSlash(properties.getIssuerUri().toString());
        String discovered = stripTrailingSlash(discovery.issuer());
        if (!configured.equals(discovered)) {
            throw new IllegalStateException(
                    "OIDC issuer mismatch. Configured='" + configured + "', discovered='" + discovered + "'.");
        }
    }

    private String stripTrailingSlash(String value) {
        while (value.endsWith("/")) {
            value = value.substring(0, value.length() - 1);
        }
        return value;
    }

    private HttpRequest.Builder formPost(URI uri, Map<String, String> form) {
        String body = encodeForm(form);
        return HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(15))
                .header("Accept", "application/json")
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(body));
    }

    private String encodeForm(Map<String, String> form) {
        StringBuilder result = new StringBuilder();
        for (Map.Entry<String, String> entry : form.entrySet()) {
            if (entry.getValue() == null || entry.getValue().isBlank()) {
                continue;
            }
            if (!result.isEmpty()) {
                result.append('&');
            }
            result.append(urlEncode(entry.getKey()))
                    .append('=')
                    .append(urlEncode(entry.getValue()));
        }
        return result.toString();
    }

    private String urlEncode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private void addClientIdentity(Map<String, String> form) {
        if (properties.getClientAuthentication() != OidcProperties.ClientAuthentication.CLIENT_SECRET_BASIC) {
            form.put("client_id", properties.getClientId());
        }
    }

    private void addPostSecretIfNeeded(Map<String, String> form) {
        if (properties.getClientAuthentication() == OidcProperties.ClientAuthentication.CLIENT_SECRET_POST) {
            form.put("client_secret", properties.getClientSecret());
        }
    }

    private void addBasicAuthIfNeeded(HttpRequest.Builder builder) {
        if (properties.getClientAuthentication() != OidcProperties.ClientAuthentication.CLIENT_SECRET_BASIC) {
            return;
        }

        // OAuth 2.0 client_secret_basic uses application/x-www-form-urlencoded encoding
        // before Base64 encoding the client_id:client_secret pair.
        String userPass = urlEncode(properties.getClientId()) + ":" + urlEncode(properties.getClientSecret());
        String basic = Base64.getEncoder().encodeToString(userPass.getBytes(StandardCharsets.UTF_8));
        builder.header("Authorization", "Basic " + basic);
    }

    private HttpResponse<String> send(HttpRequest request) {
        try {
            return httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("HTTP request was interrupted.", e);
        } catch (IOException e) {
            throw new IllegalStateException("OIDC HTTP request failed: " + e.getMessage(), e);
        }
    }

    private void require2xx(String operation, HttpResponse<String> response) {
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            JsonNode error = readTree(response.body());
            String description = text(error, "error_description");
            String code = text(error, "error");
            throw new IllegalStateException(
                    operation + " failed with HTTP " + response.statusCode()
                            + (code == null ? "" : " - " + code)
                            + (description == null ? "" : ": " + description));
        }
    }

    private <T> T read(String json, Class<T> type) {
        try {
            return objectMapper.readValue(json, type);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Could not parse OIDC JSON response.", e);
        }
    }

    private JsonNode readTree(String json) {
        try {
            return objectMapper.readTree(json == null || json.isBlank() ? "{}" : json);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Could not parse OIDC JSON response.", e);
        }
    }

    private String text(JsonNode node, String name) {
        JsonNode child = node.get(name);
        return child == null || child.isNull() ? null : child.asText();
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    private void sleep(long seconds) {
        try {
            Thread.sleep(Duration.ofSeconds(seconds).toMillis());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while waiting for OIDC authorization.", e);
        }
    }
}
