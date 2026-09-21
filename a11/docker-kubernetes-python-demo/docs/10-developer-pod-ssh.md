# A Developer Pod for Java and C++ (with SSH from Outside the Cluster)

*A "devbox": one pod per developer, with the JDK, Maven, Gradle, gcc/clang/cmake/gdb, Go, git and
friends pre-installed, a persistent home directory, and an SSH port reachable from your laptop —
so you can `ssh`, run VS Code Remote-SSH or JetBrains Gateway against it, and build inside the
cluster next to the services you are working on. Current as of September 2026 (Ubuntu 24.04,
Temurin JDK 25 LTS, Gradle 9.6, Go 1.27, clang 18).*

| Part | What you learn |
|---|---|
| [1](#part-1--step-by-step) | Build the image, deploy, SSH in, use it from VS Code |
| [2](#part-2--what-is-in-the-box) | The image, the StatefulSet, the Service, the policy |
| [3](#part-3--how-ssh-into-a-pod-works) | sshd as a non-root user, host keys that survive restarts, key-only auth |
| [4](#part-4--daily-use) | Tunnels to cluster services, port-forwards for your dev server, `kubectl` from inside |
| [5](#part-5--best-practices) | Immutable tool images, one pod per person, source-IP restrictions, cost |
| [6](#part-6--gotchas) | The things that bite |
| [7](#part-7--pros-and-cons) | Devbox pod vs laptop vs Codespaces/DevPod vs a VM |

---

## Part 1 — Step by step

```bash
# 0. an SSH key on your laptop (skip if ~/.ssh/id_ed25519.pub exists)
ssh-keygen -t ed25519 -C "me@laptop"

# 1. build the image (kind: docker build + kind load; AKS: az acr build — 5–10 minutes the first time)
./scripts/devbox.sh build

# 2. deploy: namespace, your public key as a Secret, StatefulSet + 10 Gi volume, Service, NetworkPolicy
./scripts/devbox.sh deploy -k ~/.ssh/id_ed25519.pub

# 3a. kind: tunnel and log in
./scripts/devbox.sh open            # keeps a port-forward on localhost:2222
ssh -p 2222 dev@localhost
# 3b. AKS: the Service is a LoadBalancer on port 22
./scripts/devbox.sh status          # prints  ssh dev@<public ip>
ssh dev@<public ip>

# 4. inside
java -version && mvn -v && gradle --version | head -3 && gcc --version | head -1 && clang --version | head -1 && go version
cmake --version | head -1 && gdb --version | head -1
```

**VS Code**: install *Remote - SSH*, add to `~/.ssh/config`:

```
Host devbox
  HostName localhost        # or the LoadBalancer IP
  Port 2222                 # 22 on AKS
  User dev
  IdentityFile ~/.ssh/id_ed25519
```

then *Remote-SSH: Connect to Host… → devbox*. JetBrains Gateway works the same way.

**Try the examples on it** (the Java and Go OIDC clients from tutorial 11 build there):

```bash
ssh -p 2222 dev@localhost
git clone <your fork of this repo> work/demo && cd work/demo/examples/oidc-java-cli && mvn -q package
cd ../oidc-go-cli && go mod tidy && go build .
```

---

## Part 2 — What is in the box

| Piece | File | Notes |
|---|---|---|
| Image | `images/devbox/Dockerfile` | Ubuntu 24.04 + build-essential, gcc/g++, clang/clangd/clang-format/clang-tidy/lldb, gdb, valgrind, cmake, ninja, ccache, Boost/OpenSSL/curl dev headers, **Temurin JDK 25**, Maven, **Gradle 9.6**, **Go 1.27**, kubectl, Helm 4, git, jq, tmux, vim, python3 |
| SSH server | `images/devbox/sshd_config`, `entrypoint.sh` | `sshd` on **2222**, run as user `dev` (uid 1000), keys only, host key generated once and stored on the volume |
| Namespace | `k8s/devbox/devbox.yaml` | `devbox`, Pod Security *baseline* |
| StatefulSet `devbox` | same | 1 replica, `runAsNonRoot`, all capabilities dropped, requests 0.5 CPU/1 Gi, limits 2 CPU/4 Gi, `volumeClaimTemplates` → PVC `home-devbox-0` mounted at `/home/dev` |
| Secret `devbox-ssh` | created by the script | your `authorized_keys`, mounted read-only at `/etc/devbox/authorized_keys` |
| Service `devbox-ssh` | same | port 22 → 2222; the script makes it `LoadBalancer` (cloud) or `NodePort 30022` (kind) |
| NetworkPolicy | same | ingress only on 2222, egress unrestricted (package registries, git) |
| Script | `scripts/devbox.sh` | `build · deploy [-k key.pub] · open [port] · ssh · status · destroy` |

Why a **StatefulSet** and not a Deployment: a StatefulSet gives the pod a stable name
(`devbox-0`) and a PVC that is *not* deleted when the pod is rescheduled — your clones, build
caches and shell history survive restarts and node upgrades.

---

## Part 3 — How SSH into a pod works

1. `kubectl` (or the cloud load balancer) delivers TCP to the pod's port 2222.
2. `sshd` runs **as the `dev` user**, not root. OpenSSH allows this; the only account it can log
   you into is that same user, privilege separation runs without a chroot, and no process in the
   pod ever has root — the same posture as the app pods.
3. It reads your public key from the Secret mount (`AuthorizedKeysFile /etc/devbox/authorized_keys`),
   passwords are disabled (`PasswordAuthentication no`, `UsePAM no`).
4. The **host key** lives at `/home/dev/.ssh/host/` on the persistent volume. It is generated on
   the first start and reused, so your laptop's `known_hosts` entry stays valid across pod restarts.
   (The first `status` prints the fingerprint — compare it on first connect.)
5. Rotate access by updating the Secret: `kubectl -n devbox create secret generic devbox-ssh
   --from-file=authorized_keys=... --dry-run=client -o yaml | kubectl apply -f -` — mounted secrets
   refresh within about a minute, no restart needed.

Alternatives to consider: `kubectl exec -it devbox-0 -- bash` needs no SSH at all (fine for quick
checks, but no agent forwarding, no scp, no IDE integration); **Tailscale/Teleport** give
identity-aware SSH without a public IP; **Bastion + VPN** is the enterprise default.

---

## Part 4 — Daily use

```bash
# reach cluster services from the devbox (it is INSIDE the cluster network)
curl http://python-demo-api.python-demo/health
curl http://keycloak.keycloak/realms/demo/.well-known/openid-configuration | jq .issuer

# forward a dev server running in the devbox (port 3000) to your laptop
ssh -p 2222 -L 3000:localhost:3000 dev@localhost

# forward a cluster service THROUGH the devbox (e.g. Keycloak) to your laptop
ssh -p 2222 -L 8080:keycloak.keycloak:80 dev@localhost

# kubectl from inside: give the pod a ServiceAccount with the rights you want (not by default)
kubectl create serviceaccount dev -n devbox && kubectl create rolebinding dev-view --clusterrole=view --serviceaccount=devbox:dev -n python-demo
kubectl -n devbox patch statefulset devbox -p '{"spec":{"template":{"spec":{"serviceAccountName":"dev"}}}}'

# copy files
scp -P 2222 -r ./myproject dev@localhost:work/
rsync -e 'ssh -p 2222' -av ./myproject/ dev@localhost:work/myproject/
```

Build caches: keep `~/.m2`, `~/.gradle`, `~/go/pkg`, `~/.cache/ccache` on the volume (they are
under `/home/dev`, so they already are). 10 Gi fills up fast with Gradle + Go caches — resize the
PVC (`kubectl -n devbox edit pvc home-devbox-0`, if the storage class allows expansion) or raise
the request in `devbox.yaml` before the first deploy.

---

## Part 5 — Best practices

* **One pod per developer**, named after them (`devbox-alice`); never share a home volume.
* **Immutable tool image**: add tools in the Dockerfile and rebuild, don't `apt install` inside
  (the default pod can't anyway — no root). Tag images (`devbox:2026.09`) and keep the Dockerfile
  in git so everyone gets the same toolchain.
* **Keys, not passwords**; rotate by updating the Secret; use short-lived certificates (Teleport,
  `step-ca`) when you outgrow static keys.
* **Restrict who can reach port 22**: `loadBalancerSourceRanges` on the Service and/or a CIDR in the
  NetworkPolicy `ipBlock` (`hosts.exposePorts[].source`-style office/VPN range). On AKS also set
  an NSG rule. Or don't expose it at all and use `open` (port-forward through the API server,
  which is already authenticated) — the default on kind.
* **Resource limits** that match the work: javac/Gradle happily use 2 CPUs and 4 Gi; give C++
  builds `-j` no larger than the CPU limit or the pod gets throttled.
* **Least privilege**: no ServiceAccount token by default (`automountServiceAccountToken`), add a
  scoped RoleBinding only when needed; Pod Security *baseline* on the namespace.
* **Cost**: on AKS the pod holds 0.5 CPU/1 Gi 24×7 plus a public IP. Scale to zero when idle:
  `kubectl -n devbox scale statefulset devbox --replicas=0` (the volume stays).
* **Backups**: the PVC is the developer's data — snapshot it (Azure Disk snapshots) or keep work in git.

---

## Part 6 — Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` | wrong key, or the Secret has another key | `./scripts/devbox.sh deploy -k <the .pub you use>`; `ssh -v` shows which key was offered |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` | the PVC was deleted (new host key), or you point at a different devbox | remove the line from `~/.ssh/known_hosts`; keep the volume next time |
| `sudo: unable to …` / `apt` fails | the pod runs as uid 1000 with no capabilities | rebuild the image with the tool; or run a root variant (`runAsUser: 0`, add `SETUID/SETGID/CHOWN/DAC_OVERRIDE`) — not recommended |
| Pod `Pending` forever | no PVC provisioner / storage class | kind ships `standard`; on AKS `managed-csi` is default; `kubectl get sc` |
| `ImagePullBackOff` on AKS | image built into ACR but the cluster can't pull | ACR must be attached (`--attach-acr`); `DEVBOX_IMAGE=<acr>/devbox:1.0.0` if you used a different name |
| Build ran out of memory | `javac`/`gradle -j` beyond the limit → OOMKilled | raise `resources.limits.memory`; `GRADLE_OPTS=-Xmx2g`; `cmake --build -j2` |
| Slow first `docker build` | Adoptium, Gradle and Go downloads (~500 MB) | normal; later builds use the layer cache |
| `kind` NodePort 30022 not reachable from the laptop | kind doesn't publish node ports unless mapped at cluster creation | use `open` (port-forward) or add `extraPortMappings` to `kind-config.yaml` |
| VS Code Remote-SSH fails with "bad configuration option" | wrong `Port`/`User` in `~/.ssh/config` | see the snippet in Part 1 |
| Home directory empty after re-deploy | PVC name changed (StatefulSet renamed) | keep the StatefulSet name; PVCs are `home-<statefulset>-<n>` |

---

## Part 7 — Pros and cons

| | Devbox pod (this) | Your laptop | GitHub Codespaces / DevPod / Coder | A VM (tutorial 05) |
|---|---|---|---|---|
| Same toolchain for everyone | yes (one image) | no | yes | with Ansible, yes |
| Next to cluster services (DNS, latency, policies) | yes | no (port-forwards) | no (unless self-hosted in-cluster) | same VNet on Azure |
| Persistent, backed-up workspace | PVC | local disk | managed | disk |
| IDE experience | Remote-SSH / Gateway | native | browser or Remote-SSH | Remote-SSH |
| Cost when idle | pod resources (scale to 0) | none | per-hour | VM per-hour (stop it) |
| Setup effort | this script | none | account + config | more moving parts |
| Best for | working *on* cluster services, teaching, consistent CI-like builds | everything else | teams that already use them | non-Kubernetes projects |
