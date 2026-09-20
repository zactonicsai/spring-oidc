package com.example.oidccli.oidc;

import com.fasterxml.jackson.annotation.JsonProperty;

public record DeviceAuthorizationResponse(
        @JsonProperty("device_code") String deviceCode,
        @JsonProperty("user_code") String userCode,
        @JsonProperty("verification_uri") String verificationUri,
        @JsonProperty("verification_uri_complete") String verificationUriComplete,
        @JsonProperty("expires_in") long expiresIn,
        Long interval
) {
    public long pollingIntervalSeconds() {
        return interval == null ? 5L : Math.max(1L, interval);
    }
}
