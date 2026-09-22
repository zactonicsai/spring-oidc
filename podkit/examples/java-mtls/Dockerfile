# One image for both the server and the client; the PodConfig `command` picks which to run.
#   docker build -t ghcr.io/acme/java-mtls:1.0.0 examples/java-mtls
# Single-file source launch (java File.java) needs a JDK, not a JRE. For production, compile
# ahead of time and use a jre/jlink image (smaller, faster start).
FROM eclipse-temurin:21-jdk-jammy
RUN useradd --uid 1000 --create-home app
WORKDIR /app
COPY Server.java Client.java ./
USER 1000
CMD ["java", "/app/Server.java"]
