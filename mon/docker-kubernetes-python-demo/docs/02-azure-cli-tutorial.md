# The Same Store, In the Cloud: Azure with the `az` CLI

*Read `01-kubernetes-tutorial-grocery-store-edition.md` first. This document assumes you ran the
local demo and now want the identical app on Azure — with the same `app.config.yaml`, the same
Helm chart, and one extra thing: real money. Everything here is current as of September 2026
(AKS Kubernetes 1.34–1.36, AzureRM/az CLI 2.7x, Cilium as the recommended network policy engine).*

| Part | What you learn |
|---|---|
| [1](#part-1--step-by-step-the-whole-azure-path) | Step by step: log in → registry → images → cluster → deploy → test → (VM) → destroy |
| [2](#part-2--azure-ideas-you-need) | Subscriptions, resource groups, ACR, AKS, managed identities, Key Vault, NSGs, load balancers |
| [3](#part-3--phase-by-phase-every-azure-script) | Every `scripts/azure/*.sh` explained: the `az` commands, what to look at, what it costs |
| [4](#part-4--best-practices) | Naming, identity, cost control, networking, secrets, upgrades |
| [5](#part-5--pros-and-cons) | `az` CLI vs Portal vs Terraform; AKS vs a VM vs Container Apps; AKS Automatic |

---

## Part 1 — Step by step: the whole Azure path

### What you are about to build

```
Azure subscription
└── resource group rg-python-demo                       (one bag; delete it, everything's gone)
    ├── ACR  pythondemoacr<6 chars>.azurecr.io           (image warehouse: python-demo-web, python-demo-api)
    ├── AKS  aks-python-demo   2 × Standard_B2ms nodes    (managed Kubernetes, Cilium network policy)
    │     └── namespace python-demo — the SAME Helm release as on your laptop,
    │           web Service = LoadBalancer → public IP,  api = ClusterIP (private)
    ├── Key Vault kv-python-demo-<6 chars>                (where API_TOKEN really lives)
    └── (optional) VM vm-python-demo + NSG + public IP    (the "no Kubernetes" path, cloud-init configured)
```

### Step 0 — Requirements

* An Azure subscription where you can create resources (a free trial or a Visual Studio credit works).
* The `az` CLI: https://learn.microsoft.com/cli/azure/install-azure-cli (`az version` ≥ 2.70).
* `kubectl`, `helm` (v4) and `python3` from the local tutorial. Docker is **not** required
  (images are built in the cloud by ACR Tasks).
* About **US$ 0.15–0.30 per hour** while the cluster runs (two B2ms VMs + a public IP + Basic ACR).
  The control plane is free on the `free` tier. **Run `99-destroy.sh` when you stop.**

### Step 1 — Log in and check the config

```bash
./scripts/azure/00-login.sh          # opens a browser; then registers resource providers
make show                            # region eastus, node size, VM on/off, Key Vault on/off
```

Change the region or sizes in `app.config.yaml` → `targets.azure` if you like. To use a specific
subscription: `cp .env.example .env` and set `AZ_SUBSCRIPTION=<name or id>`.

### Step 2 — Run the whole thing

```bash
./scripts/azure/run-all.sh           # ≈ 15 minutes; or: make az-up
```

Phases 0–8 run in order (details in Part 3). At the end you get a public URL like
`http://20.51.12.34:80` and `all Azure tests passed`. Open it in a browser: same page as locally,
but now the pod name is on an Azure node, and your friends can open it too.

### Step 3 — Look around

```bash
kubectl get nodes -o wide                                  # Azure VMs
kubectl -n python-demo get pods,svc,hpa,networkpolicy      # EXTERNAL-IP on the web service
./scripts/azure/12-status.sh                               # everything in the resource group
./scripts/azure/09-network.sh nsg                          # the cloud firewall rules Azure created
./scripts/azure/07-scale.sh status                         # node pool + HPA
```

### Step 4 — Try the other dials

```bash
./scripts/azure/09-network.sh lock-to-me      # only YOUR IP can reach the site; unlock with `unlock`
./scripts/azure/08-secrets.sh set API_TOKEN "rotated-$(date +%s)" && ./scripts/azure/08-secrets.sh deploy
./scripts/azure/07-scale.sh load 90           # HPA scales pods; if nodes fill up, the cluster autoscaler adds a VM
./scripts/azure/10-create-vm.sh               # the plain-VM path (Part 3, phase 10)
./scripts/azure/11-run-ansible.sh             # configure that VM with Ansible instead of bash
```

### Step 5 — Destroy (really)

```bash
./scripts/azure/99-destroy.sh        # deletes the resource group; purges the Key Vault name
```

Check the Portal → Resource groups the next day to be sure it's gone. A forgotten cluster costs
about **$150/month**.

---

## Part 2 — Azure ideas you need

| Azure thing | Grocery-store analogy | In one sentence |
|---|---|---|
| **Subscription** | the company's bank account | Everything you create is billed here; you can have several. |
| **Resource group (RG)** | one shopping bag | A folder for resources that live and die together. `az group delete` empties the bag. |
| **Region** (`eastus`) | which city the store is in | Data centre location; keep all resources of one app in one region. |
| **ACR** — Azure Container Registry | the image warehouse | A private Docker registry: `<name>.azurecr.io`. Basic tier ≈ $5/month. |
| **ACR Tasks** (`az acr build`) | the warehouse builds the boxes for you | Uploads your source folder, builds the image in Azure, stores it. No local Docker needed. |
| **AKS** — Azure Kubernetes Service | a store where Azure runs the manager's office | Managed Kubernetes: Azure operates the control plane (free tier: $0), you pay for the node VMs. |
| **Node pool** | the shop floor staff | A group of identical VMs that run pods. `system` pool + optional `user` pools. |
| **Cluster autoscaler** | hiring extra staff when it's busy | Adds/removes node VMs between `minCount` and `maxCount` based on pending pods. |
| **Managed identity** | a staff badge instead of a password | An Azure identity attached to a resource (AKS, VM). Azure gives it tokens; you never store a secret. |
| **RBAC role assignment** | what the badge opens | "Identity X has role Y on scope Z", e.g. the AKS kubelet identity has **AcrPull** on the registry. |
| **Workload identity** | badges for individual pods | Pods get Azure identities via OIDC federation — e.g. to read Key Vault — without any secret. |
| **Key Vault** | the safe in the manager's office | Stores secret values, keys and certificates; access controlled by RBAC; every read is logged. |
| **Secrets Store CSI driver** | the safe delivers straight to the shelf | AKS add-on that mounts Key Vault secrets into pods and can sync them into Kubernetes Secrets. |
| **NSG** — Network Security Group | the fence with gates | A firewall on a subnet or NIC: allow/deny rules by port, protocol, source, priority. |
| **Load balancer / public IP** | the store's phone number in the phone book | A Kubernetes `LoadBalancer` Service makes AKS create an Azure LB rule + public IP. |
| **VM** — Virtual Machine | one delivery truck you drive yourself | A plain Linux server; you install and run everything (here: via cloud-init or Ansible). |
| **cloud-init** | the checklist taped inside the truck | Runs once at first boot: writes files, installs packages, runs scripts. |
| **Tags** | price stickers | `project=python-demo`, `owner=…` on every resource, so cost reports can be filtered. |

### How AKS is different from kind

| | kind (laptop) | AKS (Azure) |
|---|---|---|
| Nodes | Docker containers | Azure VMs in a node pool |
| Control plane | inside one container | run by Microsoft; you don't see the VMs |
| Images | `kind load docker-image` | pulled from ACR with the cluster's identity |
| Public access | `kubectl port-forward` | `Service type=LoadBalancer` → real public IP |
| Network policy | kube-network-policies | Cilium (eBPF), Azure NPM (retiring), or Calico |
| metrics-server | you install it | built in |
| Secrets at rest | plain etcd | encrypted; Key Vault integration |
| Cost | free | ≈ $0.10/h per B2ms node + LB + IP + ACR |

---

## Part 3 — Phase by phase: every Azure script

All scripts source `scripts/azure/lib.sh`, which loads `build/config.env` (from
`app.config.yaml`), checks that you're logged in, and derives globally-unique names:
`AZ_ACR_NAME = pythondemoacr + 6 chars of your subscription id`,
`AZ_KEYVAULT_NAME = kv-python-demo-<6 chars>`. Override in `.env` with `AZ_ACR_NAME_OVERRIDE`
/ `AZ_KEYVAULT_NAME_OVERRIDE` if a name is taken.

### Phase 0 — `00-login.sh`: *sign in, pick the account, unlock the departments*

```bash
az login                                   # browser; `az login --use-device-code` on servers
az account set --subscription "<name>"     # if you have several
az provider register --namespace Microsoft.ContainerService --wait   # (and Registry, Compute, Network, KeyVault, ManagedIdentity)
```

**Resource providers** are Azure's "departments". A new subscription has most of them switched
off; the first `az aks create` would fail with *MissingSubscriptionRegistration*. Registering is
one-time and free. (Terraform's AzureRM 5.0 provider stopped auto-registering them for the same
least-privilege reason — see the Terraform tutorial.)

### Phase 1 — `01-create-resources.sh`: *the bag and the warehouse*

```bash
az group create --name rg-python-demo --location eastus --tags project=python-demo owner=platform-team
az acr check-name --name pythondemoacrXXXXXX            # names are global: letters+digits, 5–50 chars
az acr create -g rg-python-demo -n pythondemoacrXXXXXX --sku Basic --admin-enabled false
```

`--admin-enabled false` is deliberate: the "admin user" is a single shared username/password for
the whole registry. We never need it — AKS and the VM pull with **identities**.

### Phase 2 — `02-build-push-images.sh`: *the warehouse packs the boxes*

```bash
az acr build --registry pythondemoacrXXXXXX \
  --image python-demo-web:1.0.0 --image python-demo-web:latest \
  --file apps/web/Dockerfile --platform linux/amd64 apps/web
az acr repository list -n pythondemoacrXXXXXX -o table
az acr repository show-tags -n pythondemoacrXXXXXX --repository python-demo-web
```

`az acr build` zips the context folder, uploads it, builds inside Azure (ACR Tasks) and pushes.
Pros: no local Docker, always `linux/amd64`, build logs in Azure. Cons: a few cents per build
minute, needs network upload of the context (keep `.dockerignore` tidy).
*Local alternative:* `az acr login -n <acr>` then `docker build/tag/push` — the login is
token-based and expires after 3 hours.

### Phase 3 — `03-create-aks.sh`: *build the store, hire the manager's office*

```bash
az aks get-versions -l eastus -o table        # pick a GA version (1.34 / 1.35 / 1.36 right now)
az aks create -g rg-python-demo -n aks-python-demo -l eastus \
  --tier free \
  --node-vm-size Standard_B2ms --node-count 2 \
  --enable-cluster-autoscaler --min-count 1 --max-count 3 \
  --network-plugin azure --network-plugin-mode overlay \
  --network-dataplane cilium --network-policy cilium \
  --enable-managed-identity \
  --attach-acr pythondemoacrXXXXXX \
  --enable-oidc-issuer --enable-workload-identity \
  --enable-addons azure-keyvault-secrets-provider \
  --generate-ssh-keys
```

Line by line:

| Flag | Why |
|---|---|
| `--tier free` | No uptime SLA on the API server; $0. Use `standard` (~$73/month) for anything real. |
| `--node-vm-size Standard_B2ms` | 2 vCPU / 8 GB burstable — cheapest size that runs comfortably. |
| `--enable-cluster-autoscaler --min-count 1 --max-count 3` | node scaling (see tutorial 01, Part 8). |
| `--network-plugin azure --network-plugin-mode overlay` | **Azure CNI Overlay**: pods get IPs from a private overlay range, so you don't burn VNet addresses. Microsoft's default recommendation. |
| `--network-dataplane cilium --network-policy cilium` | **Cilium** enforces NetworkPolicy with eBPF (fast, observable). Azure NPM is being retired (Windows Sept 2026, Linux Sept 2028) — don't start new clusters on it. |
| `--enable-managed-identity` | the cluster gets its own identity (default since 2024, stated for clarity). |
| `--attach-acr` | grants the kubelet identity **AcrPull** on the registry → no `imagePullSecrets`. |
| `--enable-oidc-issuer --enable-workload-identity` | lets pods get Azure identities (reading Key Vault without secrets). |
| `--enable-addons azure-keyvault-secrets-provider` | installs the Secrets Store CSI driver + Azure provider. |
| `--generate-ssh-keys` | SSH key for the nodes (rarely used; `az aks command invoke` is the modern way in). |

Creation takes 5–10 minutes. Look: `az aks show ... --query '{version:kubernetesVersion, policy:networkProfile.networkPolicy}'`.

**AKS Automatic** (GA 2025) is the alternative: Microsoft picks node sizes, enables autoscaling
(Karpenter/NAP), policies, and upgrades for you. Great for teams that want "just run my pods";
less to learn but less to configure — it's what you'd use for a real workload without a platform
team. This project uses the standard tier so every choice is visible.

### Phase 4 — `04-get-credentials.sh`: *get the keys to the office*

```bash
az aks get-credentials -g rg-python-demo -n aks-python-demo --overwrite-existing
kubectl config current-context        # aks-python-demo
kubectl get nodes -o wide
```

This merges an `aks-python-demo` context into `~/.kube/config`. Your kind context is still
there — `kubectl config use-context kind-python-demo` switches back. **Always check the
context before `delete` or `helm uninstall`.**

### Phase 5 — `05-deploy-helm.sh`: *the same department plan*

```bash
python3 tools/appconfig.py render helm --registry pythondemoacrXXXXXX.azurecr.io   # global.imageRegistry
helm upgrade --install python-demo helm/python-demo -n python-demo --create-namespace \
  -f build/helm-values.yaml -f build/secrets-values.yaml \
  --set publicServiceType=LoadBalancer --wait --timeout 5m
kubectl -n python-demo get svc -w      # EXTERNAL-IP goes <pending> → 20.x.x.x in ~60 s
```

Only two things differ from the laptop: the registry prefix on the images, and
`publicServiceType=LoadBalancer`, which makes Azure create a load-balancer rule, a public IP,
and an NSG rule for port 80 — **for the `web` service only**, because only it has
`expose: public`. `api` stays `ClusterIP`.

### Phase 6 — `06-test.sh`: *inspection, cloud edition*

Same checks as locally, through the public IP: health, page, web→api, *api is not public*
(its Service type is `ClusterIP`), stranger pod blocked by Cilium, `helm test`.

### Phase 7 — `07-scale.sh pods|nodes|autoscaler|load|status`: *two kinds of scaling*

```bash
az aks nodepool show -g rg-python-demo --cluster-name aks-python-demo -n nodepool1 \
   --query '{count:count, min:minCount, max:maxCount, autoscale:enableAutoScaling}'
az aks update -g rg-python-demo -n aks-python-demo --update-cluster-autoscaler --min-count 1 --max-count 5
az aks scale  -g rg-python-demo -n aks-python-demo --node-count 3     # manual: only when the autoscaler is OFF
```

Pods scale with the HPA exactly as on kind (AKS ships metrics-server). Nodes scale with the
cluster autoscaler when pods are `Pending` for lack of CPU/memory. `load 90` reuses the local
load generator so you can watch both happen.

### Phase 8 — `08-secrets.sh create|set|deploy|csi`: *the safe*

```bash
az keyvault create -n kv-python-demo-XXXXXX -g rg-python-demo -l eastus --enable-rbac-authorization true
az role assignment create --role "Key Vault Secrets Officer" --assignee-object-id <you> --scope <vault id>
az keyvault secret set --vault-name kv-python-demo-XXXXXX --name API-TOKEN --value 's3cret'
az keyvault secret show --vault-name kv-python-demo-XXXXXX --name API-TOKEN --query value -o tsv
```

* **RBAC mode** (`--enable-rbac-authorization`) replaces the legacy "access policies": the
  same role model as everything else in Azure.
* Key Vault secret names use dashes, so `API_TOKEN` is stored as `API-TOKEN`; the script converts.
* `deploy` reads the values from Key Vault into a temporary `secrets.env`, runs phase 5 (the
  chart's checksum annotation restarts the api pods), then deletes the file. Your laptop never
  keeps the value.
* `csi` prints a `SecretProviderClass` for the **production** pattern: the CSI driver mounts the
  Key Vault secret directly into the pod and syncs it into a Kubernetes Secret, using the
  add-on's identity — no laptop, no `helm --set`, automatic rotation.

### Phase 9 — `09-network.sh policies|nsg|lock-to-me|unlock`: *three fences*

* `policies` — the Cilium-enforced NetworkPolicies (pod ↔ pod), same as local.
* `nsg` — lists the NSG rules Azure manages in the **node resource group** (`MC_rg-python-demo_...`).
  You'll see the port-80 rule the LoadBalancer Service created.
* `lock-to-me` — `helm upgrade --set publicServiceSourceRanges={YOUR_IP/32}` sets
  `loadBalancerSourceRanges` on the Service; AKS turns that into an NSG rule, so only your IP can
  open the site. This is the cheapest "private preview" you can get.

### Phase 10 — `10-create-vm.sh`: *the delivery truck (no Kubernetes)*

```bash
python3 tools/appconfig.py render cloudinit --registry <acr>.azurecr.io     # build/cloud-init.yaml (≈15 KB)
az vm create -g rg-python-demo -n vm-python-demo -l eastus \
  --image Ubuntu2404 --size Standard_B1s --admin-username azureuser --generate-ssh-keys \
  --assign-identity '[system]' --public-ip-sku Standard --nsg-rule NONE \
  --custom-data build/cloud-init.yaml
az vm open-port -g rg-python-demo -n vm-python-demo --port 22 --priority 1000   # one per hosts.exposePorts
az vm open-port -g rg-python-demo -n vm-python-demo --port 80 --priority 1010
az role assignment create --role AcrPull --assignee-object-id <vm identity> --scope <acr id>
```

`--custom-data` hands the rendered **cloud-init** file to the VM. At first boot it writes
`/opt/python-demo/{host-config.env,host-files.tsv,env/*.env,setup.sh,configure.sh}` and runs
`setup.sh` (packages, Docker, `ufw`, users) then `configure.sh` (downloads `sources.files`,
writes `/etc/python-demo/config.env`, logs in to ACR **with the VM's managed identity**, runs
the web + api containers). `--nsg-rule NONE` + explicit `open-port` calls means the NSG contains
*only* the ports listed in `hosts.exposePorts`. Watch it: `ssh azureuser@<ip> sudo tail -f /var/log/cloud-init-output.log`.

### Phase 11 — `11-run-ansible.sh`: *the same truck, configured by Ansible*

Writes `ansible/inventory/azure.ini` with the VM's IP and runs `ansible/site.yml`, which reads
`app.config.yaml` directly. It is idempotent: on a VM already configured by cloud-init it reports
mostly `ok`, proving the two methods agree. See `05-base-linux-setup-and-ansible.md`.

### Phase 12 — `12-status.sh` and Phase 99 — `99-destroy.sh`

`az resource list -g rg-python-demo -o table` shows the bag's contents. `az group delete --yes
--no-wait` empties it in the background, and `az keyvault purge` releases the vault name (soft
delete would otherwise reserve it for 90 days).

---

## Part 4 — Best practices

**Naming and organisation**
* One resource group per app per environment (`rg-python-demo-dev`, `-prod`); never mix.
* Tag everything (`project`, `owner`, `environment`, `managed-by`) — cost analysis filters by tag.
* Globally-unique names (ACR, Key Vault, storage) get a stable suffix; the scripts derive one
  from your subscription id, Terraform keeps a random one in state.

**Identity over secrets**
* Never enable the ACR admin user; attach ACR to AKS, give the VM a managed identity with `AcrPull`.
* Use workload identity for pods that call Azure APIs; use the Key Vault CSI driver for secrets.
* Give humans **Key Vault Secrets Officer** (or **User**), not Owner, and only on the vault.

**Networking**
* Azure CNI Overlay + Cilium for new clusters. Default-deny NetworkPolicies in every app namespace.
* Expose one front door. For HTTPS and hostnames, install an ingress controller
  (Application Gateway for Containers, or NGINX/Traefik) and set `kubernetes.ingress` in the config.
* Restrict `loadBalancerSourceRanges` for anything not meant for the public.
* Lock the VM's SSH rule to your IP (`hosts.exposePorts[].source: YOUR_IP/32`) or use Azure Bastion.

**Cost**
* `tier: free`, B-series VMs and `minCount: 1` for learning; **stop the cluster** when idle:
  `az aks stop -g rg-python-demo -n aks-python-demo` (and `az aks start`). Or destroy it — it's 15 minutes to rebuild.
* Set a **budget alert** in Cost Management. Delete public IPs and load balancers you don't use.

**Upgrades and reliability (when it's real)**
* `tier: standard` + `--zones 1 2 3` node pools + `minReplicas: 2` + PodDisruptionBudgets.
* Turn on **automatic upgrade channels** (`--auto-upgrade-channel patch`) and node OS auto-upgrades.
* Enable **Container Insights / managed Prometheus + Grafana** for monitoring; **Defender for Containers** for image scanning.
* Keep AKS within the supported version window (N-2); AKS long-term support (LTS) exists for 1.27+ if you need to stay longer.

---

## Part 5 — Pros and cons

### `az` CLI vs Azure Portal vs Terraform

| | `az` CLI scripts (this doc) | Portal (clicking) | Terraform (`03-terraform-tutorial.md`) |
|---|---|---|---|
| Learning | best: every step visible, easy to run one at a time | easiest first day; hard to repeat | steepest; need HCL + state concepts |
| Repeatability | good (idempotent scripts) | poor — nobody remembers the clicks | excellent — the code *is* the environment |
| Drift detection | none | none | `terraform plan` shows what changed |
| Deleting | `az group delete` | manual | `terraform destroy` |
| Team use / CI | fine for small teams | no | the standard |
| Best for | learning, one-offs, glue in pipelines | exploring, checking bills | anything long-lived or shared |

### AKS vs a plain VM vs Azure Container Apps

| | AKS (Kubernetes) | VM + Docker (phase 10) | Azure Container Apps |
|---|---|---|---|
| What you manage | pods, charts, policies; Azure runs the control plane | everything: OS patches, Docker, firewall, restarts | just containers + scaling rules; Azure runs the (hidden) Kubernetes |
| Scaling | HPA + cluster autoscaler | manual (bigger VM or more VMs + your own LB) | built in (KEDA), scale to zero |
| Networking control | full (NetworkPolicy, ingress, CNI choice) | ufw + NSG | limited but simple |
| Cost floor | ≈ $75/month (1 small node + IP) | ≈ $8/month (B1s) | $0 at zero scale |
| Portability | high — same chart runs on kind, EKS, GKE | high — it's a Linux box | low — Azure-specific config |
| Best for | multi-service apps, teams, platform work | one service, batch jobs, learning Linux | small apps, APIs, event-driven workloads |

### AKS Standard (this project) vs AKS Automatic

| | Standard | Automatic |
|---|---|---|
| Node pools | you choose sizes and counts | node auto-provisioning picks and scales them |
| Upgrades, policies, monitoring | opt-in flags | on by default, Microsoft-managed |
| Control / learning value | maximum | minimum — that's the point |
| Best for | learning, platform teams, special requirements | "I just want my app to run well" |
