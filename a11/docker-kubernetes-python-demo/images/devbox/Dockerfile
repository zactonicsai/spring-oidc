# =============================================================================
# devbox — a developer workspace pod for Java and C++ (and Go) work, reachable over SSH.
#   * Temurin JDK 25 (LTS), Maven, Gradle 9    * gcc/g++/clang 18, cmake, ninja, gdb, lldb, valgrind
#   * Go 1.27 (for the OIDC Go client)         * git, curl, jq, vim, tmux, python3, kubectl, helm
#   * sshd runs as the unprivileged user "dev" on port 2222 (key auth only; no root in the pod)
# Rebuild the image to add tools ("immutable dev box"); the home directory lives on a PersistentVolume.
# =============================================================================
FROM ubuntu:24.04

ARG GO_VERSION=1.27.0
ARG GRADLE_VERSION=9.6.0
ARG KUBECTL_VERSION=v1.34.1
ARG TARGETARCH=amd64
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# --- base tools + C/C++ toolchain ----------------------------------------------------------
RUN apt-get update -q && apt-get install -y -q --no-install-recommends \
      ca-certificates curl wget gnupg openssl git openssh-server sudo locales tzdata \
      build-essential gcc g++ clang clangd clang-format clang-tidy lldb gdb valgrind \
      cmake ninja-build pkg-config autoconf automake libtool ccache \
      libssl-dev libcurl4-openssl-dev zlib1g-dev libboost-dev \
      python3 python3-pip python3-venv jq vim nano tmux less unzip zip rsync htop strace ltrace \
      apt-transport-https \
 && rm -rf /var/lib/apt/lists/*

# --- Java: Temurin 25 LTS from Adoptium, Maven from apt ------------------------------------------
RUN curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo "$VERSION_CODENAME") main" > /etc/apt/sources.list.d/adoptium.list \
 && apt-get update -q && apt-get install -y -q --no-install-recommends temurin-25-jdk maven \
 && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/temurin-25-jdk-${TARGETARCH}

# --- Gradle (apt's is ancient) ------------------------------------------------------------------
RUN curl -fsSL -o /tmp/gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
 && unzip -q /tmp/gradle.zip -d /opt && ln -s /opt/gradle-${GRADLE_VERSION} /opt/gradle && rm /tmp/gradle.zip
ENV PATH=/opt/gradle/bin:$PATH

# --- Go -----------------------------------------------------------------------------------------
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH=/usr/local/go/bin:/home/dev/go/bin:$PATH

# --- kubectl + helm (handy inside the cluster) --------------------------------------------------
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

# --- the developer user -----------------------------------------------------------------------------
# uid 1000 is taken by "ubuntu" in the 24.04 image; reuse it as "dev" so PVC ownership stays 1000.
RUN userdel -r ubuntu 2>/dev/null; useradd -m -u 1000 -s /bin/bash dev \
 && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev && chmod 0440 /etc/sudoers.d/dev
# NOTE: sudo only works if the pod runs the container as root-capable; with the default non-root
#       securityContext it is inert. Rebuild the image to add tools (recommended) — see docs/10.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY sshd_config /etc/devbox/sshd_config
RUN chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /etc/devbox && chown -R dev:dev /etc/devbox

USER dev
WORKDIR /home/dev
EXPOSE 2222
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
