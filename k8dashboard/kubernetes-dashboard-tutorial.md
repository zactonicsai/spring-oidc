# Kubernetes Control Dashboard — Tutorial

*Written for a middle-school reading level. Version facts are current as of September 24, 2026; the "Check it yourself" links at the end are the official sources.*

Kubernetes (say "koo-ber-NET-eez"; people write **K8s** because there are 8 letters between the K and the s) is a program that runs your apps on a group of computers and keeps them running. This tutorial starts with one complete, working example — a Kubernetes cluster on your own laptop plus the dashboard pointed at it — and then explains everything you saw, piece by piece.

---

## Part 1 — Step by step: the dashboard on a laptop cluster

You will end up with: a real one-computer Kubernetes cluster, the dashboard reading from it, a sample web app you scale up and down, and a pod you delete on purpose to watch Kubernetes replace it.

### What you need

- A computer with Windows, macOS or Linux and about 4 GB of free memory.
- **Docker Desktop** (free for personal use) — it includes Kubernetes. If you prefer, **minikube** or **kind** work the same way (commands for them are in step 2).
- The dashboard file `index.html` (download it from the dashboard's *Connect* section, or copy the page HTML into a text file).

### Step 1 — Turn on Kubernetes in Docker Desktop

1. Install and open Docker Desktop.
2. Open **Settings → Kubernetes**.
3. Tick **Enable Kubernetes**, then **Apply & restart**. Docker downloads the Kubernetes parts (a few minutes the first time).
4. When the Kubernetes indicator at the bottom turns green, you have a cluster.

Docker Desktop also installs `kubectl`, the command-line tool that talks to Kubernetes.

### Step 2 — Check that kubectl can see the cluster

Open a terminal (PowerShell, Terminal.app, or a Linux shell) and run:

```bash
kubectl config use-context docker-desktop
kubectl get nodes
```

You should see one line like:

```
NAME             STATUS   ROLES           AGE   VERSION
docker-desktop   Ready    control-plane   2m    v1.36.4
```

`Ready` means the computer (the *node*) is healthy and can run apps. The `VERSION` column is your Kubernetes version — remember it for Part 4.

> **Using minikube or kind instead?**
> `minikube start --kubernetes-version=v1.37.1` or
> `kind create cluster --name lab --image kindest/node:v1.37.1`
> then `kubectl get nodes` exactly as above.

### Step 3 — Put the dashboard where kubectl can serve it

1. Make an empty folder called `k8s-dash`.
2. Save the dashboard as `index.html` inside it.

Why a folder? Web browsers block a page from talking to a server at a different address unless that server says it is allowed (a rule called **CORS**). Kubernetes does not say that. The trick is to let `kubectl proxy` serve **both** the page and the API from one address, so the browser is happy.

### Step 4 — Start the proxy

In the terminal, from the folder that *contains* `k8s-dash`:

```bash
kubectl proxy --port=8001 --www=./k8s-dash --www-prefix=/ui/
```

Leave this running. It prints `Starting to serve on 127.0.0.1:8001`. The proxy only listens on your own computer, and it signs every request with your kubectl credentials, so the page never needs a password or token.

### Step 5 — Open the dashboard, sign in, switch to Live mode

1. In your browser open **http://localhost:8001/ui/**
2. The first time, the dashboard asks you to sign in. Use the default administrator **admin / admin**; it immediately asks you to choose a new password (8+ characters). This account and everything about access control is stored only in your browser.
3. In the *Connect* section choose **Live (real API)**.
4. Leave *API server URL* **blank** (blank means "same address as this page").
5. Click **Connect to cluster**.

The status at the top changes to *Live · v1.36.x* and every section fills with real data: one node, the control-plane pods in the `kube-system` namespace, CoreDNS, and so on. Open the **API console** tab under *Commands* to watch the exact requests the page made, such as `GET /api/v1/nodes`.

### Step 6 — Add a sample app

1. Go to **Commands → Add**. The box already contains a small, well-written manifest: a *Deployment* named `hello` running two copies of the `nginx` web server, and a *Service* that gives them one address.
2. Click **Check config first**. Everything should be green (current API versions, resource limits, health probes, a pinned image tag).
3. Click **Apply (create or update)**.

Watch *Deployments*: `hello` shows `0/2`, then `1/2`, then `2/2` as the pods start. In the *Cluster map* two new green squares appear on the node.

The same thing from the command line would be:

```bash
kubectl apply --server-side -f hello.yaml
kubectl get deployment hello
```

### Step 7 — Scale, watch logs, break and heal

- **Scale**: *Commands → Configure → Scale a deployment*, choose `default/hello`, set replicas to 4, click **Scale**. Two more squares appear. The "What just happened" box shows the kubectl version: `kubectl scale deployment/hello --replicas=4`.
- **Logs**: *Logs*, pick a `hello` pod, click **Fetch logs**. You see nginx's start-up messages. Type `error` in the filter box to show only problem lines.
- **Heal**: *Pods*, click **Delete** on any `hello` pod. Within seconds a new pod with a different name appears. The Deployment noticed it had 3 pods instead of 4 and made another. This is Kubernetes' most important habit: it keeps fixing the difference between what you asked for and what exists.
- **Clean up** when you are done:

```bash
kubectl delete deployment hello
kubectl delete service hello
```

Press Ctrl-C in the terminal to stop the proxy.

### Step 8 — Check your versions

In *Versions & upgrades* click **Fill from cluster**, then **Check for conflicts**. The checker tells you whether your Kubernetes version is still supported, whether your node and `kubectl` are within the allowed "skew", and whether your Helm version matches. Then pick a target in *Upgrade planner* and click **Build my upgrade plan** to see the order of operations for Docker Desktop (in this case: update Docker Desktop itself).

That is the whole loop: **see → change → verify**. Everything else in this tutorial explains the pieces you just used.

---

## Part 2 — Background: what Kubernetes is and why it exists

### The problem it solves

A modern app is not one program; it is many small programs (a web server, an API, a database, a worker that sends emails) running on many computers. Somebody has to start them, restart them when they crash, spread them across machines, give them addresses, and add copies when traffic grows. Doing that by hand does not scale. Kubernetes does it automatically from a written description of what you want.

### The school picture

| Kubernetes word | In a school | What it really is |
| --- | --- | --- |
| Cluster | The whole school | A set of computers managed together |
| Control plane | The front office | The parts that make decisions |
| Node | A classroom | One computer that runs apps |
| Pod | A desk | The smallest unit Kubernetes runs; holds one or more containers |
| Container | A student at the desk | Your app, packed with everything it needs |
| Deployment | The rule "this class always has 3 desks" | Keeps N copies running and updates them gradually |
| Service | The classroom's phone number | One stable address that reaches whichever pods are healthy now |
| Namespace | A grade level | A folder that keeps groups of objects apart |

### Containers in one paragraph

A **container image** (for example `nginx:1.29.1`) is a frozen, ready-to-run copy of a program plus the files it needs. A **container** is that image running. Images live in registries such as Docker Hub or GitHub Container Registry. Because the image contains everything, the same one runs identically on a laptop, in Amazon, Google, Microsoft, IBM or your own servers. Kubernetes' job is to run containers — it does not build them.

---

## Part 3 — The pieces, one at a time

### The control plane (the brain)

| Part | Job | Plain words |
| --- | --- | --- |
| **kube-apiserver** | Receives every request and checks permissions | The front desk. Everything — kubectl, this dashboard, even the other control-plane parts — goes through it |
| **etcd** | Stores the cluster's state | The notebook. Lose it and the cluster forgets everything, so back it up |
| **kube-scheduler** | Picks a node for each new pod | The seating planner |
| **kube-controller-manager** | Runs the loops that fix differences | The checkers: "3 wanted, 2 running → make one" |
| **cloud-controller-manager** | Talks to the cloud (load balancers, disks) | Only on cloud clusters |

**Managed clusters** (EKS, GKE, AKS, IBM Cloud, OKE, DigitalOcean) run all of this for you and hide the machines. You can still ask `/readyz` and `/livez` — the dashboard's *Control plane* section shows the answer. **Self-managed** clusters (Docker Desktop, minikube, kind, kubeadm, OpenShift, RKE2) run them as pods in the `kube-system` namespace, so you will see them in the Pods list too.

### Nodes (the workers)

Each node runs three helpers: the **kubelet** (the node's agent that starts pods and reports back), a **container runtime** (usually containerd, which actually runs containers) and **kube-proxy** or a CNI plugin (the networking). A node is `Ready` when the kubelet is healthy. `SchedulingDisabled` means someone **cordoned** it — it keeps running its pods but takes no new ones, which is normal during maintenance.

### Pods and their statuses

You rarely create pods yourself; Deployments do. Statuses you will meet:

| Status | Meaning | What to do |
| --- | --- | --- |
| Pending | Waiting for a node or an image | Wait; check Events if it lasts |
| ContainerCreating | Starting | Wait |
| Running, Ready 1/1 | Good | Nothing |
| ImagePullBackOff / ErrImagePull | Image name, tag or registry login is wrong | Fix the image |
| CrashLoopBackOff | App starts, crashes, restarts | Read logs with "Previous container" |
| OOMKilled | Used more memory than its limit | Raise the limit or fix the leak |
| Completed | A one-off job finished | Nothing |
| Terminating | Shutting down | Wait (30 s default) |

**Logs** are what the app printed. **Events** are what Kubernetes did to the app. When a pod is stuck, read the events first — the dashboard's *Events* button on each pod shows them.

### Deployments and rolling updates

A Deployment holds the pod template (which image, how much CPU/memory, which health checks) and the number of replicas. When you change the template — a new image, a new setting — Kubernetes performs a **rolling update**: it starts one new pod, waits for it to be healthy, retires one old pod, and repeats. If the new version never becomes healthy, the rollout stalls instead of taking the app down, and `kubectl rollout undo deployment/NAME` goes back.

### Services

Pods have short lives and changing IP addresses. A Service is a fixed name and address that always points at the healthy pods whose labels match its **selector** (for example `app=web`). Types: **ClusterIP** (inside the cluster only), **NodePort** (also a port on every node), **LoadBalancer** (a public address from the cloud), **ExternalName** (a DNS alias). Inside the cluster, DNS makes `web.default.svc.cluster.local` — or simply `web` — resolve to the Service.

### YAML and the API

Everything you saw is an **object** with an `apiVersion`, a `kind`, `metadata` (name, namespace, labels) and a `spec` (what you want). The API server exposes each object over HTTPS at a predictable path:

```
/api/v1/namespaces/default/pods/web-abc            (core objects)
/apis/apps/v1/namespaces/default/deployments/web   (grouped objects)
```

The group and version in the path are exactly what you write as `apiVersion:` in YAML. HTTP verbs map to actions: GET (read/list), POST (create), PATCH (partial change), DELETE. `kubectl` is just a friendly client for this API; run `kubectl get pods --v=8` to watch it make the same calls the dashboard shows in its API console.

**Two ways to change a cluster**

- *Declarative* — write YAML and `kubectl apply` it (the dashboard uses **server-side apply**, which creates or updates in one call). The file is the truth; keep it in version control.
- *Imperative* — direct orders: `kubectl scale`, `kubectl rollout restart`, `kubectl set image`, `kubectl delete pod`. Great for experiments; for real systems, write the result into YAML afterwards so it is not forgotten.

### Getting in: kubeconfig, tokens and permissions

To reach a cluster you need its address and proof of identity (a certificate or a **token**). kubectl keeps both in `~/.kube/config` (the **kubeconfig**). Each hosting provider has a one-line command that writes it:

| Hosting | Sign-in command |
| --- | --- |
| Docker Desktop | `kubectl config use-context docker-desktop` |
| minikube | `minikube start` (writes the config for you) |
| kind | `kind create cluster --name lab` |
| Amazon EKS | `aws eks update-kubeconfig --region us-east-1 --name my-cluster` |
| Google GKE | `gcloud container clusters get-credentials my-cluster --region us-central1` |
| Azure AKS | `az aks get-credentials --resource-group my-rg --name my-cluster` |
| Red Hat OpenShift | `oc login https://api.cluster.example.com:6443 --token=...` |
| IBM Cloud | `ibmcloud ks cluster config --cluster my-cluster` |
| Oracle OKE | `oci ce cluster create-kubeconfig --cluster-id <ocid> --file ~/.kube/config` |
| DigitalOcean | `doctl kubernetes cluster kubeconfig save my-cluster` |
| RKE2 / k3s | `export KUBECONFIG=/etc/rancher/rke2/rke2.yaml` on a server node |

**RBAC** (role-based access control) decides what each identity may do. Whatever your token can do, the dashboard can do too — including deleting pods. When exploring a shared cluster, use a read-only account. Never paste a token into a page you do not trust; the dashboard keeps it in memory only and forgets it when the tab closes, and the `kubectl proxy` method never needs one at all.

---

## Part 4 — Versions, upgrades and avoiding conflicts

### How versions work

Versions look like **1.37.1** = major.minor.patch.

- A new **minor** (1.36 → 1.37) comes about every four months and can add or remove features.
- **Patch** releases (1.37.0 → 1.37.1) come monthly and only fix bugs and security holes. Always take them.
- Each minor gets about **14 months** of support (12 months of patches plus 2 months of "maintenance mode"). The project keeps the newest three minors.

**Status as of September 24, 2026** (from kubernetes.io/releases):

| Minor | Status | First release | End of life |
| --- | --- | --- | --- |
| 1.38 | Next — expected December 2026 | — | — |
| **1.37** ("Garhwal") | **Current** | 2026-08-26 | 2027-10-28 |
| 1.36 | Supported (prior release) | April 2026 | 2027-06-28 |
| 1.35 | Supported | 2025-12-17 | 2027-02-28 |
| 1.34 | Maintenance mode — upgrade now | 2025-08-27 | 2026-10-27 |
| 1.33 and older | End of life — no security fixes | | |

Managed clouds usually add a new minor a few weeks to months after upstream, and may sell "extended support" for old ones. Their version pages are linked from the dashboard's hosting panel.

### Version skew: which parts may differ

Not every part must match, but the differences have limits (the official *version skew policy*):

| Part | Rule |
| --- | --- |
| kube-apiserver (HA control plane) | All API servers within one minor of each other |
| kubelet (nodes) and kube-proxy | Never newer than the API server; up to **3 minors older** |
| controller-manager, scheduler, cloud-controller-manager | Never newer than the API server; up to 1 minor older |
| kubectl | Within **one minor either way** of the API server |

So the order is always **control plane → nodes → kubectl and add-ons**, and the control plane moves **one minor at a time** (1.35 → 1.36 → 1.37, never 1.35 straight to 1.37). Nodes may jump several minors at once as long as they stay within 3 of the API server.

### Helm: the package manager

Helm installs **charts** (folders of YAML templates with default settings) as **releases**, and every `helm upgrade` creates a numbered revision you can roll back to.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-db bitnami/postgresql --set auth.password=secret
helm list -A
helm upgrade my-db bitnami/postgresql --version 16.2.0
helm rollback my-db 1
```

**Latest info:** Helm 4 is the current major version (4.0.0 shipped 2025-11-12; 4.3.0 on 2026-09-09). Charts written for Helm 3 keep working. Helm 3 only receives security fixes until **2026-11-11**, so move to Helm 4 before then.

**Compatibility rule:** each Helm minor is built against one Kubernetes minor and supports it plus the three before it.

| Helm | Works with Kubernetes |
| --- | --- |
| 4.3.x | 1.37 – 1.34 (confirm on helm.sh) |
| 4.2.x | 1.36 – 1.33 |
| 4.1.x | 1.35 – 1.32 |
| 4.0.x | 1.34 – 1.31 |
| 3.21.x | 1.36 – 1.33 |

Charts can also declare a `kubeVersion` rule in `Chart.yaml` (for example `>=1.33.0-0`). If your cluster is outside it, `helm install` refuses. The dashboard's conflict checker tests both rules for you.

### Deprecated and removed APIs

Early ("beta") API versions are switched off after a while. Applying old YAML then fails with *no matches for kind*. The most common leftovers in old tutorials:

| Old apiVersion | Kinds | Gone since | Use instead |
| --- | --- | --- | --- |
| extensions/v1beta1, apps/v1beta1, apps/v1beta2 | Deployment, DaemonSet, ReplicaSet, StatefulSet | 1.16 | apps/v1 |
| extensions/v1beta1, networking.k8s.io/v1beta1 | Ingress | 1.22 | networking.k8s.io/v1 |
| rbac.authorization.k8s.io/v1beta1 | Roles and bindings | 1.22 | rbac.authorization.k8s.io/v1 |
| batch/v1beta1 | CronJob | 1.25 | batch/v1 |
| policy/v1beta1 | PodDisruptionBudget | 1.25 | policy/v1 |
| policy/v1beta1 | PodSecurityPolicy | 1.25 | Pod Security Admission |
| autoscaling/v2beta1, v2beta2 | HorizontalPodAutoscaler | 1.25 / 1.26 | autoscaling/v2 |
| flowcontrol.apiserver.k8s.io/v1beta1–v1beta3 | FlowSchema, PriorityLevelConfiguration | 1.26 / 1.29 / 1.32 | flowcontrol.apiserver.k8s.io/v1 |

No further removals are scheduled through 1.37. Paste any YAML into the dashboard's **Config checker** to test it against a target version, or use `kubectl apply --dry-run=server` on the real cluster, or tools such as Pluto and kube-no-trouble that scan whole folders and Helm releases.

### A safe upgrade, in order

1. Read the release notes for each hop (the dashboard's planner links them).
2. Fix YAML and charts that use removed APIs.
3. Back up: an etcd snapshot on self-managed clusters; an export of your objects everywhere.
4. Upgrade the control plane one minor at a time (managed clouds do it in place; kubeadm uses `kubeadm upgrade apply`).
5. Upgrade nodes one at a time: `kubectl cordon` → `kubectl drain --ignore-daemonsets` → upgrade → `kubectl uncordon`. PodDisruptionBudgets stop a drain from taking down too many copies of an app at once.
6. Upgrade add-ons (CNI, CoreDNS, metrics-server, ingress), Helm and your own kubectl.
7. Verify: all nodes Ready, all Deployments at full replicas, no new Warning events, `helm list -A` all "deployed".

Practise on a test cluster first. The dashboard's *Upgrade planner* writes these steps out with the commands for your hosting provider.

---

## Part 4b — Access control: users, roles, OIDC and LDAP

### What RBAC is

RBAC means **role-based access control**. Instead of giving each person a list of powers, you create a few **roles** (viewer, developer, operator, admin) and **bind** people or groups to them. Kubernetes works the same way: a `Role` (one namespace) or `ClusterRole` (everywhere) lists verbs on resources, and a `RoleBinding` or `ClusterRoleBinding` connects it to a `User`, `Group` or `ServiceAccount`.

### In the dashboard (Access control section)

| Tab | What it does |
| --- | --- |
| My access | Your groups, roles and permissions — and the same access written as Kubernetes RBAC YAML you can `kubectl apply` |
| Users | Local accounts stored in the browser with salted PBKDF2 password hashes; `admin` is created on first run |
| Roles | Built-in roles (viewer, developer, operator, admin) plus custom ones you build by ticking permissions |
| Bindings | "This user or group gets this role in these namespaces" — the way OIDC/LDAP groups become roles |
| Identity providers | OIDC settings (issuer, client ID, claims) and LDAP settings (server, base DNs, filters) |
| Audit log | Every attempted action, allowed or denied, with who did it |

Every button checks the rules before it works: a viewer's Delete buttons are locked, a developer bound only to `default` cannot scale `kube-system/coredns`, and only "everywhere" bindings can grant cluster-level powers (nodes, raw API, Live mode, access management). Denied attempts are still written to the audit log.

**Try it:** sign out and sign in as the practice identity `carol` (group *viewers*). Try to delete a pod — it is locked, and the attempt appears in the audit log. Sign in as `bob` (*dev-team-a*, developer in `default` only) and scale `web`: allowed. Scale `coredns` in `kube-system`: denied.

**Be honest about what this protects.** The rules live in your browser's local storage. They prevent mistakes and teach the model, but anyone with the file and the browser's developer tools can change them. The real wall is Kubernetes RBAC on the credential you connect with — which is exactly why OIDC matters.

### OIDC: each person uses their own identity

OpenID Connect lets a website ask an identity provider (Keycloak, Dex, Okta, Auth0, Microsoft Entra ID, Google) "who is this?". The provider returns a signed **ID token** with the person's name and — if configured — their **groups**.

1. At the provider, create a *public* client (no secret) that allows PKCE and lists the dashboard's address as a redirect URI. Add a mapper so the ID token contains a groups claim.
2. In the dashboard, fill in the issuer URL, client ID, username claim and groups claim (the presets fill common values), save, and click *Test discovery*.
3. Sign in with OIDC. Your groups map to roles through bindings — for example, group `platform-admins` → role `admin`.
4. Tick "Use the ID token as the Kubernetes bearer token" and configure the API server to trust the provider (the dashboard prints the `AuthenticationConfiguration` snippet). Then bind groups on the cluster too:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins
subjects:
- kind: Group
  name: "oidc:platform-admins"   # prefix comes from the API server's groups prefix
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

Managed clouds have a switch for this: EKS identity provider configs, GKE Identity Service, AKS Microsoft Entra ID integration, IBM Cloud and OpenShift identity providers.

The hosted copy of the dashboard cannot reach an identity provider (browsers block it); run the page from your own address, for example through `kubectl proxy --www` as in Part 1.

### LDAP and Active Directory

LDAP is the company phone book (Active Directory is Microsoft's version). Browsers cannot open LDAP connections, so a helper sits in the middle:

- **Through an identity provider (recommended):** Dex or Keycloak reads the directory and issues OIDC tokens that carry the person's groups. Fill in the LDAP fields (server, bind DN, user and group base DNs, filters, attributes), click *Generate Dex connector config*, add it to Dex, and point the OIDC settings at Dex. Kubernetes trusts the same tokens.
- **Through an auth service:** a small program you host that accepts a username and password, binds to LDAP as that user, looks up the groups and returns `{"user": "...", "groups": [...]}` (optionally with a Kubernetes token). Simple, but you own it.

Always use `ldaps://` so passwords never travel unencrypted, and use a read-only bind account for searches.

### Best practices for access

- Bind to **groups**, not people; new colleagues then get the right role automatically.
- Give the smallest role that does the job; use "everywhere" bindings only when needed.
- Change the default `admin` password immediately (the dashboard forces this) and keep a second admin binding so you cannot lock yourself out.
- Prefer OIDC over shared kubeconfigs so the cluster's audit log shows real names.
- Check what a person can do on the real cluster with `kubectl auth can-i --list --as=oidc:maria --as-group=oidc:dev-team-a`.

---

## Part 5 — Where to run Kubernetes: options with pros and cons

| Option | Best for | Pros | Cons |
| --- | --- | --- | --- |
| **Docker Desktop** (local) | Learning, testing | Free; one click; same kubectl as the cloud | One node only; stops with your laptop; no public load balancer |
| **minikube** (local) | Learning; choosing exact versions | Pick any Kubernetes version; add-ons; multi-node possible | Needs a VM or Docker underneath; not for real users |
| **kind** (local) | Automated tests, CI | Starts in under a minute; control-plane nodes visible | Throw-away clusters; no cloud load balancer |
| **Amazon EKS** | Teams already on AWS | Managed, patched control plane; deep IAM/ELB/EBS integration; Auto Mode can run nodes | Hourly cost; control plane invisible; extended support costs extra |
| **Google GKE** | Fast access to new versions; hands-off nodes | Release channels; Autopilot; automatic upgrades in maintenance windows | Auto-upgrades can surprise you; control plane invisible |
| **Azure AKS** | Microsoft shops; slow upgraders | Free control plane; LTS versions; strong Windows support | Newest versions arrive as previews; many add-ons to choose |
| **Red Hat OpenShift** | Enterprises wanting a full platform | Visible control-plane nodes; operators upgrade everything together; support | Subscription; Kubernetes version lags upstream; its own `oc` tooling |
| **IBM Cloud Kubernetes Service** | IBM customers; compliance needs | Managed control plane; OpenShift option; multi-zone | Manual worker updates by default; smaller ecosystem |
| **Oracle OKE / DigitalOcean** | Cost-sensitive teams | Free control plane; simple pricing | Fewer regions, services and add-ons |
| **SUSE Rancher / RKE2 / k3s** | Own hardware, edge devices | Runs anywhere; multi-cluster management; k3s fits a Raspberry Pi | You own upgrades and backups |
| **kubeadm (self-managed)** | Learning the internals; private clouds | No cloud fee; every component visible | You patch, back up and monitor everything |

A sensible path: learn on Docker Desktop or minikube, run real users on a managed cloud, and pick OpenShift or Rancher when you need many clusters on your own hardware.

---

## Part 6 — Best practices checklist

**Writing manifests**

- Use current `apiVersion`s (`apps/v1`, `networking.k8s.io/v1`, `batch/v1`, `autoscaling/v2`).
- Pin image tags (`nginx:1.29.1`), never `:latest` — you cannot tell what is running or roll back otherwise.
- Set `resources.requests` and `resources.limits` on every container so the scheduler can plan and one bug cannot starve a node.
- Add a `readinessProbe` (may it receive traffic?) and a `livenessProbe` (should it be restarted?).
- Run at least 2 replicas of anything users depend on, and add a PodDisruptionBudget.
- Always set `metadata.namespace`; put team apps in their own namespaces.
- Keep YAML in version control and apply it from there (GitOps tools such as Argo CD or Flux automate this).

**Operating**

- Take patch releases promptly; plan minor upgrades before the old version's end-of-life date.
- Keep every component inside the skew policy; upgrade control plane → nodes → kubectl.
- Match Helm to the cluster (n-3 rule) and move to Helm 4 before Helm 3 support ends in November 2026.
- Back up etcd (self-managed) or export objects (everywhere) before every upgrade.
- Give people and tools the least RBAC permission that works; use read-only accounts for dashboards.
- Ship logs and metrics somewhere durable (a cloud logging service, Loki, Prometheus/Grafana); the node keeps only recent logs.

**Debugging order**

1. `kubectl get pods -A` — what is not Running/Ready?
2. `kubectl describe pod NAME` — read the Events at the bottom.
3. `kubectl logs NAME` (add `--previous` after a crash).
4. `kubectl get events -A --sort-by=.lastTimestamp` — what happened cluster-wide?
5. `kubectl top nodes` / `kubectl top pods` — is something out of CPU or memory?

---

## Part 7 — Quick reference

```bash
# See things
kubectl get nodes -o wide
kubectl get deployments,services,pods -A
kubectl describe pod NAME -n NAMESPACE
kubectl logs NAME -n NAMESPACE --tail=200 -f
kubectl get events -A --sort-by=.lastTimestamp
kubectl top nodes && kubectl top pods -A
kubectl version && helm version

# Change things
kubectl apply --server-side -f app.yaml
kubectl scale deployment/web --replicas=4
kubectl rollout restart deployment/web
kubectl set image deployment/web web=nginx:1.29.1
kubectl rollout undo deployment/web
kubectl delete pod NAME
kubectl create configmap app-settings --from-literal=KEY=value

# Maintain things
kubectl cordon NODE && kubectl drain NODE --ignore-daemonsets --delete-emptydir-data
kubectl uncordon NODE
kubectl apply --dry-run=server -f app.yaml          # validate without saving
kubectl proxy --port=8001 --www=./k8s-dash --www-prefix=/ui/   # serve the dashboard + API together
```

**Glossary in one line each:** *cluster* — a group of computers managed together · *node* — one computer · *pod* — smallest unit, one or more containers with one IP · *container* — a running image · *image* — a packaged program · *Deployment* — keeps N pod copies and rolls updates · *ReplicaSet* — the Deployment's counter · *Service* — a stable address for pods · *Ingress* — HTTP routing from outside · *Namespace* — a folder · *label/selector* — tags and the rules that match them · *ConfigMap/Secret* — settings and passwords · *kubelet* — the node agent · *etcd* — the cluster database · *CNI* — the network plugin · *Helm chart/release* — a package and an installed copy · *cordon/drain* — pause and empty a node · *skew* — the allowed version difference · *probe* — a health check · *RBAC* — who may do what.

---

## Check it yourself — official sources

- Kubernetes documentation: https://kubernetes.io/docs/home/
- Using RBAC authorization: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Authentication (OIDC tokens, structured authentication config): https://kubernetes.io/docs/reference/access-authn-authz/authentication/
- Dex LDAP connector: https://dexidp.io/docs/connectors/ldap/ — Keycloak LDAP federation: https://www.keycloak.org/docs/latest/server_admin/index.html#_ldap
- Kubernetes basics (interactive): https://kubernetes.io/docs/tutorials/kubernetes-basics/
- Releases and support windows: https://kubernetes.io/releases/
- Version skew policy: https://kubernetes.io/releases/version-skew-policy/
- Deprecated API migration guide: https://kubernetes.io/docs/reference/using-api/deprecation-guide/
- Upgrading a cluster: https://kubernetes.io/docs/tasks/administer-cluster/cluster-upgrade/
- kubectl quick reference: https://kubernetes.io/docs/reference/kubectl/quick-reference/
- kubectl proxy: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_proxy/
- The Kubernetes API: https://kubernetes.io/docs/concepts/overview/kubernetes-api/
- Helm documentation: https://helm.sh/docs/ — version support policy: https://helm.sh/docs/topics/version_skew/
- Docker Desktop Kubernetes: https://docs.docker.com/desktop/features/kubernetes/
- minikube: https://minikube.sigs.k8s.io/docs/start/ — kind: https://kind.sigs.k8s.io/docs/user/quick-start/
- Amazon EKS: https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html — versions: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- Google GKE: https://cloud.google.com/kubernetes-engine/docs — release channels: https://cloud.google.com/kubernetes-engine/docs/concepts/release-channels
- Azure AKS: https://learn.microsoft.com/en-us/azure/aks/ — versions: https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions
- Red Hat OpenShift: https://docs.redhat.com/en/documentation/openshift_container_platform
- IBM Cloud Kubernetes Service: https://cloud.ibm.com/docs/containers?topic=containers-getting-started — versions: https://cloud.ibm.com/docs/containers?topic=containers-cs_versions
- Pluto (finds deprecated APIs): https://github.com/FairwindsOps/pluto — kube-no-trouble: https://github.com/doitintl/kube-no-trouble
