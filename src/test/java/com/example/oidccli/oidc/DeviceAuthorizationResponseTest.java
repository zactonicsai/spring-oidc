package com.example.oidccli.oidc;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class DeviceAuthorizationResponseTest {

    @Test
    void defaultsPollingIntervalToFiveSeconds() {
        var response = new DeviceAuthorizationResponse(
                "device", "user", "https://example.test/device", null, 600, null);

        assertThat(response.pollingIntervalSeconds()).isEqualTo(5L);
    }

    @Test
    void usesProviderPollingInterval() {
        var response = new DeviceAuthorizationResponse(
                "device", "user", "https://example.test/device", null, 600, 8L);

        assertThat(response.pollingIntervalSeconds()).isEqualTo(8L);
    }
}
