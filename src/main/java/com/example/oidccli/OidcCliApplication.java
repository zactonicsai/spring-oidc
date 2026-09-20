package com.example.oidccli;

import com.example.oidccli.config.OidcProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(OidcProperties.class)
public class OidcCliApplication {

    public static void main(String[] args) {
        SpringApplication.run(OidcCliApplication.class, args);
    }
}
