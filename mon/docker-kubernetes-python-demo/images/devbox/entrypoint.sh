#!/usr/bin/env bash
# First start: populate the persistent home, generate a host key (kept on the volume so the
# fingerprint survives pod restarts), then run sshd in the foreground as user "dev".
set -euo pipefail
HOME=/home/dev
[[ -f "$HOME/.bashrc" ]] || cp -n /etc/skel/.bashrc /etc/skel/.profile "$HOME/" 2>/dev/null || true
mkdir -p "$HOME/.ssh/host" "$HOME/go" "$HOME/work" && chmod 700 "$HOME/.ssh"
if [[ ! -f "$HOME/.ssh/host/ssh_host_ed25519_key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/host/ssh_host_ed25519_key"
  echo "generated host key: $(ssh-keygen -lf "$HOME/.ssh/host/ssh_host_ed25519_key.pub")"
fi
grep -q 'export PATH=/opt/gradle/bin' "$HOME/.bashrc" 2>/dev/null || cat >> "$HOME/.bashrc" <<'RC'
export PATH=/opt/gradle/bin:/usr/local/go/bin:$HOME/go/bin:$PATH
export JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
RC
[[ -r /etc/devbox/authorized_keys ]] || echo "WARNING: /etc/devbox/authorized_keys missing — mount the devbox-ssh secret"
echo "devbox ready: ssh -p 2222 dev@<host>  (java $(java -version 2>&1 | head -1 | cut -d'"' -f2), gcc $(gcc -dumpversion), go $(go version | cut -d' ' -f3))"
exec /usr/sbin/sshd -D -e -f /etc/devbox/sshd_config
