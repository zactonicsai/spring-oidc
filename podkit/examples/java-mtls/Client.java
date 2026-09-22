import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManagerFactory;
import java.io.FileInputStream;
import java.io.InputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

/**
 * Minimal mTLS client: presents its own certificate and only trusts the shared CA.
 *
 * Env: SERVER_URL (default https://java-server:8443/), INTERVAL_SECONDS (default 10, 0 = once),
 *      KEYSTORE_PATH, KEYSTORE_PASSWORD, TRUSTSTORE_PATH, TRUSTSTORE_PASSWORD (mounted by podkit).
 *
 * Run: java Client.java
 */
public class Client {
    public static void main(String[] args) throws Exception {
        String url = env("SERVER_URL", "https://java-server:8443/");
        int interval = Integer.parseInt(env("INTERVAL_SECONDS", "10"));
        SSLContext ctx = context();

        do {
            try {
                HttpsURLConnection conn = (HttpsURLConnection) new URL(url).openConnection();
                conn.setSSLSocketFactory(ctx.getSocketFactory());
                conn.setConnectTimeout(5000);
                conn.setReadTimeout(5000);
                try (InputStream in = conn.getInputStream()) {
                    System.out.println(conn.getResponseCode() + " " + new String(in.readAllBytes(), StandardCharsets.UTF_8).trim());
                }
            } catch (Exception e) {
                System.out.println("request failed: " + e); // e.g. handshake failure = wrong CA or missing client cert
            }
            if (interval > 0) Thread.sleep(interval * 1000L);
        } while (interval > 0);
    }

    static SSLContext context() throws Exception {
        KeyStore keystore = load(env("KEYSTORE_PATH", "/etc/tls/keystore/keystore.jks"), env("KEYSTORE_PASSWORD", ""));
        KeyStore truststore = load(env("TRUSTSTORE_PATH", "/etc/tls/truststore/truststore.jks"), env("TRUSTSTORE_PASSWORD", ""));
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(keystore, env("KEYSTORE_PASSWORD", "").toCharArray());
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(truststore);
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);
        return ctx;
    }

    static KeyStore load(String path, String password) throws Exception {
        KeyStore ks = KeyStore.getInstance("JKS");
        try (FileInputStream in = new FileInputStream(path)) {
            ks.load(in, password.toCharArray());
        }
        return ks;
    }

    static String env(String key, String def) {
        String v = System.getenv(key);
        return v == null || v.isEmpty() ? def : v;
    }
}
