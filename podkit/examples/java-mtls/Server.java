import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsParameters;
import com.sun.net.httpserver.HttpsServer;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.TrustManagerFactory;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.cert.X509Certificate;

/**
 * Minimal HTTPS server that REQUIRES a client certificate (mutual TLS).
 *
 * Reads the keystore/truststore that podkit mounts from Secrets:
 *   KEYSTORE_PATH, KEYSTORE_PASSWORD     -> this pod's private key + certificate (issued by the shared CA)
 *   TRUSTSTORE_PATH, TRUSTSTORE_PASSWORD -> the shared CA, so only clients with a CA-issued cert are accepted
 * Optional: PORT (default 8443).
 *
 * Run: java Server.java  (Java 11+ single-file launch)
 */
public class Server {
    public static void main(String[] args) throws Exception {
        int port = Integer.parseInt(env("PORT", "8443"));
        SSLContext ctx = Tls.context();

        HttpsServer server = HttpsServer.create(new InetSocketAddress(port), 0);
        server.setHttpsConfigurator(new HttpsConfigurator(ctx) {
            @Override
            public void configure(HttpsParameters params) {
                SSLParameters ssl = getSSLContext().getDefaultSSLParameters();
                ssl.setNeedClientAuth(true); // the whole point of mTLS
                ssl.setProtocols(new String[] {"TLSv1.3", "TLSv1.2"});
                params.setSSLParameters(ssl);
            }
        });
        server.createContext("/", exchange -> {
            String peer = "unknown";
            try {
                X509Certificate[] chain = (X509Certificate[]) exchange.getSSLSession().getPeerCertificates();
                peer = chain[0].getSubjectX500Principal().getName();
            } catch (Exception ignored) { /* cannot happen with needClientAuth, kept for clarity */ }
            byte[] body = ("hello " + peer + " from " + env("HOSTNAME", "server") + "\n").getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "text/plain");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream out = exchange.getResponseBody()) { out.write(body); }
        });
        server.start();
        System.out.println("mTLS server listening on " + port);
    }

    static String env(String key, String def) {
        String v = System.getenv(key);
        return v == null || v.isEmpty() ? def : v;
    }
}

/** Builds an SSLContext from the JKS keystore and truststore podkit provides. */
class Tls {
    static SSLContext context() throws Exception {
        KeyStore keystore = load(Server.env("KEYSTORE_PATH", "/etc/tls/keystore/keystore.jks"), Server.env("KEYSTORE_PASSWORD", ""));
        KeyStore truststore = load(Server.env("TRUSTSTORE_PATH", "/etc/tls/truststore/truststore.jks"), Server.env("TRUSTSTORE_PASSWORD", ""));

        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(keystore, Server.env("KEYSTORE_PASSWORD", "").toCharArray());
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(truststore);

        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);
        return ctx;
    }

    static KeyStore load(String path, String password) throws Exception {
        KeyStore ks = KeyStore.getInstance("JKS"); // Java also reads PKCS12 transparently
        try (FileInputStream in = new FileInputStream(path)) {
            ks.load(in, password.toCharArray());
        }
        return ks;
    }
}
