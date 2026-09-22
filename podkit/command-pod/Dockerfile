# Command pod image: kubectl + Ansible (kubernetes.core, community.postgresql) + openssl + keytool + psql.
# Build once, push to your registry, and set COMMAND_POD_IMAGE (scripts) / var.image (Terraform).
#
#   docker build -t ghcr.io/your-org/podkit-command-pod:latest -f command-pod/Dockerfile .
#
# Keep it small: a slim base, no compilers, one layer per concern. It is the only image
# podkit needs besides your own workloads.
FROM python:3.12-slim

ARG KUBECTL_VERSION=v1.31.4
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl openssl postgresql-client default-jre-headless jq git tar \
 && rm -rf /var/lib/apt/lists/*

RUN ARCH="$(dpkg --print-architecture)" \
 && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" -o /usr/local/bin/kubectl \
 && chmod 0755 /usr/local/bin/kubectl

RUN pip install --no-cache-dir "ansible-core>=2.16,<2.19" kubernetes pyyaml jsonpatch psycopg2-binary

# Collections are installed system-wide so any user (uid 1000) can use them.
COPY ansible/requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml -p /usr/share/ansible/collections \
 && rm /tmp/requirements.yml

# A baked-in copy of the playbooks and scripts; scripts/configure.sh syncs a fresh copy to /work.
COPY ansible/ /opt/podkit/ansible/
COPY configure/ /opt/podkit/configure/

RUN useradd --uid 1000 --create-home --shell /bin/bash ops \
 && mkdir -p /work && chown ops:ops /work
USER ops
ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections \
    ANSIBLE_HOST_KEY_CHECKING=False \
    PATH=/usr/local/bin:/usr/bin:/bin
WORKDIR /work

CMD ["sleep", "infinity"]
