package com.example.oidccli.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.net.URI;
import java.time.Duration;

@ConfigurationProperties(prefix = "app.oidc")
public class OidcProperties {

    private URI issuerUri;
    private String clientId;
    private String clientSecret = "";
    private String scope = "openid profile email";
    private ClientAuthentication clientAuthentication = ClientAuthentication.NONE;
    private Duration pollTimeout = Duration.ofMinutes(5);
    private boolean verifyIdToken = true;
    private boolean printAccessToken = false;
    private boolean allowHttpLocalhost = true;

    public enum ClientAuthentication {
        NONE,
        CLIENT_SECRET_POST,
        CLIENT_SECRET_BASIC
    }

    public void validate() {
        if (issuerUri == null) {
            throw new IllegalArgumentException("OIDC issuer is required. Set OIDC_ISSUER_URI.");
        }
        if (clientId == null || clientId.isBlank()) {
            throw new IllegalArgumentException("OIDC client ID is required. Set OIDC_CLIENT_ID.");
        }
        if (!scopeContains("openid")) {
            throw new IllegalArgumentException("OIDC_SCOPE must include the 'openid' scope.");
        }
        if (clientAuthentication != ClientAuthentication.NONE
                && (clientSecret == null || clientSecret.isBlank())) {
            throw new IllegalArgumentException(
                    "OIDC_CLIENT_SECRET is required when client authentication is " + clientAuthentication);
        }
        validateTransport();
    }

    private boolean scopeContains(String expected) {
        if (scope == null) {
            return false;
        }
        for (String item : scope.trim().split("\\s+")) {
            if (expected.equals(item)) {
                return true;
            }
        }
        return false;
    }

    private void validateTransport() {
        String scheme = issuerUri.getScheme();
        if ("https".equalsIgnoreCase(scheme)) {
            return;
        }

        String host = issuerUri.getHost();
        boolean localhost = host != null && (
                host.equalsIgnoreCase("localhost")
                        || host.equals("127.0.0.1")
                        || host.equals("::1"));

        if (allowHttpLocalhost && "http".equalsIgnoreCase(scheme) && localhost) {
            return;
        }

        throw new IllegalArgumentException(
                "OIDC issuer must use HTTPS. HTTP is allowed only for localhost when "
                        + "OIDC_ALLOW_HTTP_LOCALHOST=true.");
    }

    public URI getIssuerUri() {
        return issuerUri;
    }

    public void setIssuerUri(URI issuerUri) {
        this.issuerUri = issuerUri;
    }

    public String getClientId() {
        return clientId;
    }

    public void setClientId(String clientId) {
        this.clientId = clientId;
    }

    public String getClientSecret() {
        return clientSecret;
    }

    public void setClientSecret(String clientSecret) {
        this.clientSecret = clientSecret;
    }

    public String getScope() {
        return scope;
    }

    public void setScope(String scope) {
        this.scope = scope;
    }

    public ClientAuthentication getClientAuthentication() {
        return clientAuthentication;
    }

    public void setClientAuthentication(ClientAuthentication clientAuthentication) {
        this.clientAuthentication = clientAuthentication;
    }

    public Duration getPollTimeout() {
        return pollTimeout;
    }

    public void setPollTimeout(Duration pollTimeout) {
        this.pollTimeout = pollTimeout;
    }

    public boolean isVerifyIdToken() {
        return verifyIdToken;
    }

    public void setVerifyIdToken(boolean verifyIdToken) {
        this.verifyIdToken = verifyIdToken;
    }

    public boolean isPrintAccessToken() {
        return printAccessToken;
    }

    public void setPrintAccessToken(boolean printAccessToken) {
        this.printAccessToken = printAccessToken;
    }

    public boolean isAllowHttpLocalhost() {
        return allowHttpLocalhost;
    }

    public void setAllowHttpLocalhost(boolean allowHttpLocalhost) {
        this.allowHttpLocalhost = allowHttpLocalhost;
    }
}
