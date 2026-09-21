# Best Practices and Pros & Cons — Every Choice in This Project

*A reference you can scan. Each section names the choice this template made, why, and what the
alternatives trade off. Current as of September 2026.*

---

## 1. Deploying to Kubernetes: kubectl vs Helm vs Kustomize vs GitOps

| | `kubectl apply -f k8s/` | Helm chart (used here) | Kustomize | GitOps (Argo CD / Flux) |
|---|---|---|---|---|
| What it is | apply YAML files | templated packages + release history | plain YAML with overlays (patch files per env) | a controller in the cluster pulls from git and applies |
| Templating | none | Go templates + values | none (patches) | uses Helm or Kustomize underneath |
| Per-environment variation | copies of files | values files | overlays | one repo/branch per env |
| Rollback | manual | `helm rollback` | git revert + apply | git revert; the controller reconciles |
| Drift correction | none | none (until next upgrade) | none | continuous |
| Learning curve | lowest | medium | low-medium | highest (extra components) |
| Best for | learning, tiny apps | apps you install repeatedly; sharing | teams that dislike templating | production fleets, many clusters |

**Practices:** keep charts generic (loop over data, as this one does); `helm lint` +
`helm template | kubeconform` in CI; pin chart versions; `--wait`; never `helm install` by hand in
production — CI or GitOps applies.

## 2. Local Kubernetes: kind vs minikube vs k3d vs Docker Desktop

| | kind (used here) | minikube | k3d (k3s in Docker) | Docker Desktop's Kubernetes |
|---|---|---|---|---|
| Runs as | Docker containers | VM or container | Docker containers | inside Docker Desktop's VM |
| Multi-node | yes (config file) | yes (`--nodes`) | yes | no |
| Startup | ~1 min | 1–2 min | ~30 s | ~1 min |
| NetworkPolicy | enforced (≥ 0.24) | needs a CNI add-on (`--cni calico`) | Traefik + k3s policy controller | not enforced |
| LoadBalancer services | needs MetalLB/cloud-provider-kind | `minikube tunnel` | built-in (k3s servicelb) | works on localhost |
| Image loading | `kind load` | `minikube image load` | `k3d image import` | shares Docker's images |
| Best for | CI, matches upstream k8s exactly | GUI add-ons, beginners on VMs | fastest, lightweight | zero setup on Mac/Windows |

**Practices:** pin node images (`kindest/node:v1.34.x@sha256:…`) for reproducible CI;
install metrics-server yourself (done); delete clusters you're not using.

## 3. Where to run in Azure: AKS vs AKS Automatic vs Container Apps vs a VM vs App Service

| | AKS Standard (used here) | AKS Automatic | Azure Container Apps | VM + Docker (also here) | App Service |
|---|---|---|---|---|---|
| You manage | node pools, add-ons, policies | almost nothing | nothing below the container | everything | nothing below the code |
| Kubernetes API | full | full | hidden | none | none |
| Scaling | HPA + cluster autoscaler | node auto-provisioning + HPA | KEDA, scale to 0 | manual | built-in autoscale |
| Network policy | Cilium/Calico | Cilium (on by default) | limited | ufw + NSG | n/a |
| Min monthly cost | ≈ $75 | ≈ $150 (standard tier required) | $0 at zero scale | ≈ $8 | ≈ $13 (Basic) |
| Best for | learning, platform teams, portability | teams that want managed opinions | microservices/APIs without k8s knowledge | single service, batch, legacy | web apps in supported runtimes |

## 4. Creating Azure resources: `az` CLI vs Portal vs Terraform vs Bicep

| | `az` CLI scripts (here) | Portal | Terraform (here) | Bicep |
|---|---|---|---|---|
| Repeatable | mostly (scripts + idempotent checks) | no | yes | yes |
| Shows changes before applying | no | no | `plan` | `what-if` |
| Multi-cloud / non-Azure things (Docker, kind, Helm) | no | no | yes | no |
| State to protect | none | none | state file | none (Azure holds deployments) |
| Best for | learning, ops glue, CI steps | exploring | long-lived environments | Azure-only IaC |

**Practices:** tag everything; one RG per app per env; register only needed providers; use
`--no-wait` for deletes; `az aks stop` when idle.

## 5. Configuring base Linux hosts: bash vs cloud-init vs Ansible vs golden images

See `05-base-linux-setup-and-ansible.md` Part 8 for the full table. Short version: **cloud-init
(or a golden image) to bootstrap, Ansible to keep hosts converged, containers for the app.**

## 6. Secrets: where the value lives

| Option | Where the value is | Rotation | Risk | Used here |
|---|---|---|---|---|
| Hard-coded in the image / YAML | git + registry | rebuild | **never do this** | — |
| Kubernetes Secret created from a git-ignored file (`secrets.env`) | your laptop + etcd (base64) | re-render + `helm upgrade` (checksum restarts pods) | laptop compromise; etcd access | local path |
| Key Vault → script → Secret | Key Vault; briefly on the laptop | `08-secrets.sh set` + `deploy` | short-lived local copy | Azure scripts |
| Key Vault → Terraform `var.secrets` → Secret | Key Vault + **Terraform state** | `apply` | state file must be protected | Terraform azure |
| Key Vault → Secrets Store CSI driver → pod | Key Vault only | automatic (`secret_rotation_enabled`) | lowest | `08-secrets.sh csi` pattern |
| External Secrets Operator | vault → Secret, continuously | automatic | low | not included (good next step) |
| Sealed Secrets / SOPS in git | encrypted in git | commit | key management | not included |

**Practices:** declare keys in the config, never values; one key per env var; RBAC on
Secrets; encryption at rest (AKS default); mask in logs; identities (managed/workload
identity) instead of passwords wherever Azure lets you; `gitleaks` in CI.

## 7. Network policy engines on AKS

| | Cilium (used here) | Azure NPM | Calico |
|---|---|---|---|
| Technology | eBPF dataplane | iptables/ipsets | iptables or eBPF |
| Status (2026) | Microsoft's recommendation, default for new work | **retiring** (Windows Sept 2026, Linux Sept 2028) | supported, open-source, more policy features (GlobalNetworkPolicy) |
| Extras | Hubble observability, FQDN egress policies (advanced container networking) | — | Calico-specific CRDs |
| Choose when | new clusters, Azure CNI Overlay | never for new clusters | you already use Calico elsewhere |

**Practices:** default-deny ingress per namespace; allow by `podSelector`; test the negative
case; add egress policies with DNS allowed first; keep `api`-style services `ClusterIP`.

## 8. Scaling options

| Dial | Mechanism | Metric | Good for |
|---|---|---|---|
| Deployment replicas | fixed count | none | predictable load, minimum footprint |
| HPA (used here) | adds/removes pods | CPU (default), memory, custom | most web/API services |
| KEDA | HPA driven by external events | queue length, HTTP RPS, cron, Kafka lag… | event-driven, scale-to-zero |
| VPA | changes requests/limits | historical usage | right-sizing; not with HPA on the same metric |
| Cluster autoscaler (used here) | adds/removes nodes | pending pods | AKS standard |
| Node auto-provisioning (Karpenter) | picks VM sizes on the fly | pending pods | AKS Automatic; heterogeneous workloads |

**Practices:** set requests; `minReplicas: 2` for user-facing services; PodDisruptionBudgets;
realistic `maxReplicas`; tune stabilisation windows; load-test before trusting the numbers.

## 9. Images

| Practice | Why |
|---|---|
| `python:3.13-slim` base, multi-stage build | small, fewer CVEs, fast pulls |
| unique tags (version or git SHA), never `latest` in a manifest | reproducible deploys, working rollbacks |
| digests for production (`@sha256:`) | immutable supply chain |
| `USER 65532`, read-only root, drop capabilities, seccomp | contain a compromise |
| pin `requirements.txt`, rebuild monthly | reproducibility + security patches |
| scan in CI (`trivy`, `docker scout`, Defender for Containers) | catch known CVEs |
| `--platform linux/amd64` (or multi-arch) | AKS nodes are amd64 by default; Apple Silicon laptops are arm64 |
| private registry + identity-based pulls | no shared passwords; audit trail |

## 10. Project structure: one config file for everything

| Pros | Cons |
|---|---|
| one place to change a port, a setting, a secret key | a custom schema to learn (small; documented in 04) |
| scripts, Helm, Terraform and Ansible can't disagree | some duplication of *parsing* logic (Python renderer + HCL module) — kept in sync by tests |
| validation catches errors before any tool runs | very unusual Kubernetes features still need chart edits |
| bootstrapping a new project is one command | — |

When this stops fitting (many teams, many charts), the natural evolution is: this config →
a Helm *library* chart or an internal developer platform (Backstage templates, Score, Radius).

## 11. General practices this template follows

* **Fail fast**: prerequisites checked, config validated, `set -euo pipefail` everywhere.
* **Idempotent everything**: scripts check before changing; Terraform/Ansible are idempotent by design.
* **Least privilege**: no ACR admin user, RBAC-mode Key Vault, resource-provider allow-list,
  default-deny network policies, non-root containers, NSG with only listed ports.
* **Observability hooks**: health endpoints, `helm test`, `kubectl top`, logs to files on hosts.
* **Cost awareness**: free tier, burstable VMs, autoscaler minimums, `99-destroy` scripts.
* **Documentation next to code**: every script has a header explaining what and why.
