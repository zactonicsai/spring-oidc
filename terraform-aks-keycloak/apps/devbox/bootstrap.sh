#!/usr/bin/env bash
# Idempotent bootstrap used when the default ubuntu:24.04 image is selected.
# Prefer building apps/devbox/Dockerfile and setting var.devbox_image to the ACR tag.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! id dev >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo dev
  echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev
fi

if [[ -n "${DEV_PASSWORD:-}" ]]; then
  echo "dev:${DEV_PASSWORD}" | chpasswd
fi

mkdir -p /home/dev/.ssh /home/dev/work /var/run/sshd
if [[ -f /etc/ssh-bootstrap/authorized_keys ]]; then
  cp /etc/ssh-bootstrap/authorized_keys /home/dev/.ssh/authorized_keys
  chmod 600 /home/dev/.ssh/authorized_keys
fi
chown -R dev:dev /home/dev

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl wget gnupg git openssh-server sudo vim unzip zip \
  build-essential cmake ninja-build gdb pkg-config clang \
  libssl-dev zlib1g-dev python3 jq tmux

# JDK 27 (Corretto), fall back to 25 if 27 package is not in this region's mirror yet.
curl -fsSL https://apt.corretto.aws/corretto.key | gpg --dearmor -o /usr/share/keyrings/corretto.gpg
echo "deb [signed-by=/usr/share/keyrings/corretto.gpg] https://apt.corretto.aws stable main" > /etc/apt/sources.list.d/corretto.list
apt-get update
if ! apt-get install -y java-27-amazon-corretto-jdk; then
  apt-get install -y java-25-amazon-corretto-jdk
fi

if [[ ! -x /opt/maven/bin/mvn ]]; then
  curl -fsSL https://archive.apache.org/dist/maven/maven-3/3.9.11/binaries/apache-maven-3.9.11-bin.tar.gz | tar -xz -C /opt
  ln -sfn /opt/apache-maven-3.9.11 /opt/maven
fi

if [[ ! -x /opt/gradle/bin/gradle ]]; then
  curl -fsSL https://services.gradle.org/distributions/gradle-9.1.0-bin.zip -o /tmp/gradle.zip
  unzip -qo /tmp/gradle.zip -d /opt
  ln -sfn /opt/gradle-9.1.0 /opt/gradle
fi

if [[ ! -x /usr/local/go/bin/go ]]; then
  curl -fsSL https://go.dev/dl/go1.25.1.linux-amd64.tar.gz | tar -xz -C /usr/local
fi

cat >/etc/profile.d/devbox.sh <<'EOF'
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
export PATH="/opt/maven/bin:/opt/gradle/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
export GOPATH="$HOME/go"
EOF

# Generate host keys if missing, then run sshd in the foreground.
ssh-keygen -A
exec /usr/sbin/sshd -D -e
