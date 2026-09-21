# Developer workstation image for AKS.
# Build and push to the Azure Container Registry created by Terraform:
#   az acr build -r <acr_name> -t devbox:27 -f apps/devbox/Dockerfile apps/devbox
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    JAVA_HOME=/usr/lib/jvm/java-27 \
    GOPATH=/home/dev/go \
    PATH=/usr/lib/jvm/java-27/bin:/usr/local/go/bin:/home/dev/go/bin:/opt/maven/bin:/opt/gradle/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg git openssh-server sudo vim nano less unzip zip \
      build-essential cmake ninja-build gdb lldb pkg-config \
      clang clang-tidy clang-format \
      libssl-dev zlib1g-dev libtool autoconf \
      python3 python3-pip \
      jq tmux htop ripgrep fd-find \
    && rm -rf /var/lib/apt/lists/*

# JDK 27 from Amazon Corretto (GA feature release as of Sep 2026).
RUN curl -fsSL https://apt.corretto.aws/corretto.key | gpg --dearmor -o /usr/share/keyrings/corretto.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/corretto.gpg] https://apt.corretto.aws stable main" > /etc/apt/sources.list.d/corretto.list \
    && apt-get update \
    && (apt-get install -y java-27-amazon-corretto-jdk || apt-get install -y java-25-amazon-corretto-jdk) \
    && rm -rf /var/lib/apt/lists/* \
    && JAVA_DIR=$(dirname $(dirname $(readlink -f $(command -v java)))) \
    && ln -sfn "$JAVA_DIR" /usr/lib/jvm/java-27

ARG MAVEN_VERSION=3.9.11
ARG GRADLE_VERSION=9.1.0
ARG GO_VERSION=1.25.1

RUN curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      | tar -xz -C /opt \
    && ln -s "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven \
    && curl -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip \
    && unzip -q /tmp/gradle.zip -d /opt \
    && ln -s "/opt/gradle-${GRADLE_VERSION}" /opt/gradle \
    && rm /tmp/gradle.zip \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
      | tar -xz -C /usr/local

RUN useradd -m -s /bin/bash -G sudo dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev \
    && mkdir -p /var/run/sshd /home/dev/work /home/dev/.ssh \
    && chown -R dev:dev /home/dev \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && echo "PermitRootLogin no" >> /etc/ssh/sshd_config

WORKDIR /home/dev/work
EXPOSE 22
USER root
CMD ["/usr/sbin/sshd", "-D", "-e"]
