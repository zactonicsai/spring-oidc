package com.example.oidccli.cli;

import com.example.oidccli.config.OidcProperties;
import com.example.oidccli.oidc.DeviceAuthorizationResponse;
import com.example.oidccli.oidc.OidcDeviceClient;
import com.example.oidccli.oidc.OidcDiscovery;
import com.example.oidccli.oidc.TokenResponse;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

@Component
public class OidcCliRunner implements ApplicationRunner {

    private final OidcDeviceClient oidc;
    private final OidcProperties properties;
    private final ObjectMapper objectMapper;

    public OidcCliRunner(OidcDeviceClient oidc, OidcProperties properties, ObjectMapper objectMapper) {
        this.oidc = oidc;
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        String command = command(args.getNonOptionArgs());

        if ("help".equals(command) || "--help".equals(command) || "-h".equals(command)) {
            printHelp();
            return;
        }

        OidcDiscovery discovery = oidc.discover();

        if ("discover".equals(command)) {
            printDiscovery(discovery);
            return;
        }

        if (!"login".equals(command)) {
            throw new IllegalArgumentException("Unknown command: " + command + ". Use 'login', 'discover', or 'help'.");
        }

        login(discovery);
    }

    private void login(OidcDiscovery discovery) throws Exception {
        DeviceAuthorizationResponse device = oidc.startDeviceAuthorization(discovery);

        System.out.println();
        System.out.println("OIDC login started");
        System.out.println("==================");
        System.out.println("1. Open: " + bestVerificationUrl(device));
        System.out.println("2. If asked, enter code: " + device.userCode());
        System.out.println("3. Sign in and approve the request.");
        System.out.println();
        System.out.println("Waiting for approval...");

        TokenResponse tokens = oidc.pollForTokens(discovery, device);

        System.out.println();
        System.out.println("Authentication successful.");
        System.out.println("Token type: " + safe(tokens.tokenType()));
        System.out.println("Expires in: " + (tokens.expiresIn() == null ? "unknown" : tokens.expiresIn() + " seconds"));
        System.out.println("Scopes: " + safe(tokens.scope()));

        if (properties.isVerifyIdToken()) {
            Jwt jwt = oidc.verifyIdToken(tokens);
            System.out.println("ID token signature/issuer/time/audience validation: OK");
            printIdentity(jwt.getClaims());
        } else {
            System.out.println("WARNING: ID token validation is disabled by configuration.");
        }

        JsonNode userInfo = oidc.fetchUserInfo(discovery, tokens);
        if (userInfo != null) {
            System.out.println();
            System.out.println("UserInfo:");
            System.out.println(objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(userInfo));
        }

        if (properties.isPrintAccessToken()) {
            System.out.println();
            System.out.println("WARNING: Printing access token because OIDC_PRINT_ACCESS_TOKEN=true");
            System.out.println(tokens.accessToken());
        } else {
            System.out.println();
            System.out.println("Access token received but not printed. Set OIDC_PRINT_ACCESS_TOKEN=true only for local debugging.");
        }
    }

    private void printIdentity(Map<String, Object> claims) {
        System.out.println();
        System.out.println("Identity claims:");
        printClaim(claims, "sub");
        printClaim(claims, "preferred_username");
        printClaim(claims, "name");
        printClaim(claims, "email");
        printClaim(claims, "iss");
        printClaim(claims, "aud");
    }

    private void printClaim(Map<String, Object> claims, String name) {
        Object value = claims.get(name);
        if (value != null) {
            System.out.println("  " + name + ": " + value);
        }
    }

    private void printDiscovery(OidcDiscovery discovery) throws Exception {
        System.out.println(objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(discovery));
    }

    private String bestVerificationUrl(DeviceAuthorizationResponse device) {
        return device.verificationUriComplete() == null || device.verificationUriComplete().isBlank()
                ? device.verificationUri()
                : device.verificationUriComplete();
    }

    private String command(List<String> nonOptionArgs) {
        return nonOptionArgs.isEmpty() ? "login" : nonOptionArgs.get(0).toLowerCase();
    }

    private String safe(String value) {
        return value == null || value.isBlank() ? "unknown" : value;
    }

    private void printHelp() {
        System.out.println("spring-oidc-cli");
        System.out.println();
        System.out.println("Commands:");
        System.out.println("  login       Start OIDC Device Authorization login (default)");
        System.out.println("  discover    Print discovered OIDC endpoints");
        System.out.println("  help        Show this help");
        System.out.println();
        System.out.println("Configuration is read from application.yml and environment variables.");
        System.out.println("Required: OIDC_ISSUER_URI and OIDC_CLIENT_ID");
    }
}
