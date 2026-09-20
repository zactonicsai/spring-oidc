package com.example.oidccli.oidc;

import com.fasterxml.jackson.annotation.JsonProperty;

public record OidcDiscovery(
        String issuer,
        @JsonProperty("authorization_endpoint") String authorizationEndpoint,
        @JsonProperty("token_endpoint") String tokenEndpoint,
        @JsonProperty("jwks_uri") String jwksUri,
        @JsonProperty("userinfo_endpoint") String userinfoEndpoint,
        @JsonProperty("device_authorization_endpoint") String deviceAuthorizationEndpoint
) {
}
