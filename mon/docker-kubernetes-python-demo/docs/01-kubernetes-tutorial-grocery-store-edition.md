# Kubernetes, Explained With a Grocery Store (and a School)

*A complete, step-by-step tutorial for beginners — middle-school reading level, professional-grade
practices. Everything here is current as of September 2026 (Kubernetes 1.34–1.36, Helm 4, kind 0.30+).*

> **How to read this.** Part 1 gets the demo running on your laptop in about 10 minutes.
> Parts 2–8 explain *what just happened* and *why*, one idea at a time, using two places you
> already understand: a **grocery store** and a **school**. Part 9 walks every script phase by phase.
> You can read straight through, or jump to a section from the table below.

| Part | What you learn |
|---|---|
| [1](#part-1--step-by-step-run-the-example-on-your-laptop) | Run the whole thing: check tools → cluster → images → deploy → test → open in browser |
| [2](#part-2--the-big-ideas) | Containers, images, registries, clusters, nodes, pods, deployments, services, namespaces |
| [3](#part-3--kubectl-the-store-managers-walkie-talkie) | `kubectl`: what it is, its grammar, the 20 commands you'll use every day |
| [4](#part-4--helm-recipe-cards-for-whole-departments) | `helm`: charts, values, releases, upgrade, rollback, lint, template, test |
| [5](#part-5--why-images-matter) | Tags, digests, layers, size, non-root, pull policies, `ImagePullBackOff` |
| [6](#part-6--controlling-network-access) | Who may talk to whom: NetworkPolicy, public vs cluster-only, cloud firewalls |
| [7](#part-7--secrets) | Config vs secrets, why base64 isn't encryption, Key Vault, rotation |
| [8](#part-8--scaling-and-controlling-scale) | Replicas, the HorizontalPodAutoscaler, resources, metrics-server, node autoscaling |
| [9](#part-9--phase-by-phase-every-script-explained) | Each script: what it runs, what to look at, what can go wrong |
| [10](#part-10--where-to-go-next) | Azure, Terraform, Ansible, the config schema |

---

## Part 1 — Step by step: run the example on your laptop

### What you are about to build

```
Your laptop
└── Docker (runs containers)
    └── kind cluster "python-demo"  (Kubernetes IN Docker: 2 containers pretend to be 2 servers)
        └── namespace python-demo
            ├── Deployment python-demo-web  (2 pods)  ──► Service python-demo-web  (public)
            └── Deployment python-demo-api  (1 pod)   ──► Service python-demo-api  (cluster-only)
                                       ▲
                         only "web" may call "api" (NetworkPolicy)
```

* **web** is a Python/Flask page. When you open it, it *itself* calls the **api** over the cluster
  network and prints the answer, plus which pod answered.
* **api** is a Python/Flask JSON service with a hidden **secret** (it shows it masked) and a
  `/api/work` endpoint that burns CPU so you can watch autoscaling.

### Step 0 — Install the tools (once)

| Tool | What it is | Install |
|---|---|---|
| Docker Desktop / Docker Engine | runs containers | https://docs.docker.com/get-docker/ |
| `kind` | makes a Kubernetes cluster out of Docker containers | `brew install kind` / https://kind.sigs.k8s.io/docs/user/quick-start/#installation |
| `kubectl` | the Kubernetes command-line tool | `brew install kubectl` / https://kubernetes.io/docs/tasks/tools/ |
| `helm` (**v4**) | the Kubernetes package manager | `brew install helm` / https://helm.sh/docs/intro/install/ |
| `python3` + `pip` | runs the config tool | usually preinstalled; `pip install -r tools/requirements.txt` |
| `curl` | sends web requests from the terminal | usually preinstalled |

> Helm 3 reached end of life in 2026. Use Helm 4. The scripts still work on Helm 3, but you
> will see deprecation warnings for renamed flags (`--atomic` → `--rollback-on-failure`).

### Step 1 — Get the code and look around

```bash
cd docker-kubernetes-python-demo
pip install -r tools/requirements.txt     # PyYAML + jsonschema for the config tool
make show                                 # summary of app.config.yaml
```

You will see something like:

```
App:        python-demo  v1.0.0   namespace=python-demo   registry=(local)
Services:
  - web      image=python-demo-web:1.0.0   ports=80->8080/TCP (public)
             replicas=2 hpa=2-5@60%cpu  config=['GREETING', 'API_URL', 'LOG_LEVEL']  secrets=[]  allowFrom=-
  - api      image=python-demo-api:1.0.0   ports=80->8080/TCP (cluster)
             replicas=1 hpa=1-4@70%cpu  config=['GREETING', 'LOG_LEVEL']  secrets=['API_TOKEN']  allowFrom=['web']
```

**`app.config.yaml` is the one file that describes the whole app.** Every script, the Helm chart,
Terraform and Ansible read it. You will edit it later; for now just notice it exists.

### Step 2 — Give the api its secret

```bash
cp secrets.env.example secrets.env   # contains API_TOKEN=change-me-local-token
chmod 600 secrets.env                # only you can read it; it is git-ignored
```

### Step 3 — Run everything

```bash
chmod +x scripts/*.sh scripts/*/*.sh setup/*.sh
./scripts/run-all.sh                 # or: make up
```

This runs six scripts in a row (each is explained in Part 9):

| Script | What it does | Takes |
|---|---|---|
| `00-check-prereqs.sh` | checks tools, validates `app.config.yaml` | 2 s |
| `01-create-cluster.sh` | creates the kind cluster + installs metrics-server | 1–2 min |
| `02-build-images.sh` | `docker build` for web and api | 1 min first time |
| `03-load-images.sh` | copies the images into the cluster's nodes | 20 s |
| `04-deploy-helm.sh` | renders values from the config and runs `helm upgrade --install` | 1 min |
| `05-test.sh` | health checks, config, secret, web→api, load balancing, network policy | 30 s |

The last lines should say `All tests passed.`

### Step 4 — Open it in your browser

```bash
./scripts/06-port-forward.sh         # or: make open
```

Open **http://localhost:8080**. You will see the greeting from the config, the name of the
**pod** that served the page, and a line *"API says: Hello from the stock room, friend!"* that
came from the api pod over the cluster network. Refresh a few times: the web pod name changes,
because there are two of them and Kubernetes takes turns.

Try these too: `http://localhost:8080/?name=YourName`, `/config`, `/api-config`, `/health`.

### Step 5 — Look inside the cluster

Open a second terminal:

```bash
kubectl get nodes                                   # the 2 "servers"
kubectl -n python-demo get pods -o wide              # 3 pods, which node they're on
kubectl -n python-demo get svc,hpa,networkpolicy     # services, autoscalers, network rules
kubectl -n python-demo logs deployment/python-demo-api --tail=5
```

### Step 6 — Play, then clean up

```bash
./scripts/07-scale.sh load 60      # hammer the api for 60 s, watch the HPA add pods
./scripts/08-secrets.sh show       # what a Secret really looks like
./scripts/09-network.sh test       # prove web→api works and stranger→api is blocked
./scripts/10-cleanup-apps.sh       # remove the app, keep the cluster
./scripts/99-destroy.sh            # delete the cluster (Docker stays)
```

That's the whole loop. Now let's understand it.

---

## Part 2 — The big ideas

### 2.1 Containers and images — *lunch boxes and the recipe for packing them*

A **container** is a running program packed together with *everything it needs*: the Python
interpreter, the Flask library, your code, the settings. It runs the same on your laptop, on a
school computer, and in the cloud — like a packed lunch box that tastes the same wherever you open it.

An **image** is the *recipe and the packed result* — a frozen, read-only snapshot. You build an
image once (`docker build`) and can start hundreds of containers from it (`docker run`). One
recipe, many lunch boxes.

The recipe is the **Dockerfile**. Ours (`apps/api/Dockerfile`) says: start from the official
`python:3.13-slim` image, install `requirements.txt`, copy `app.py`, run as a non-root user,
start `gunicorn` on port 8080. (Part 5 explains why each line matters.)

**Registry** — the *warehouse* that stores images. Docker Hub is the public one. In Part 1 there
was no warehouse: `kind load docker-image` carried the image straight from your Docker into the
cluster nodes. On Azure the warehouse is **ACR** (Azure Container Registry).

### 2.2 Cluster, nodes, control plane — *the store, the shop floor, the manager's office*

A **cluster** is the whole grocery store. It has:

* **Nodes** — the *shop floor*: computers that actually run containers. In kind, each node is a
  Docker container pretending to be a server. In Azure (AKS) each node is a real virtual machine.
* **Control plane** — the *manager's office*: the **API server** (the front desk every request
  goes through), **etcd** (the store's record book — the only place the truth is written down),
  the **scheduler** (decides which shelf/node gets each new item), and **controllers** (assistant
  managers who constantly compare "what should exist" to "what does exist" and fix the difference).

The most important idea in all of Kubernetes lives in that last sentence:

> **You don't tell Kubernetes what to *do*. You tell it what you *want* — and controllers keep
> making it true.** If a pod dies at 3 a.m., a controller notices the count is wrong and starts
> a new one. This is called being *declarative*.

School version: the principal doesn't personally teach every class. The principal publishes a
timetable ("Room 12 has math at 9:00 with 25 students"). If a teacher is sick, the office
compares the timetable to reality and sends a substitute. The timetable is your YAML.

### 2.3 Pods — *a shopping cart*

A **pod** is the smallest thing Kubernetes runs: one or more containers that share an IP address
and can share storage. Usually **one container per pod** (ours are). Think of a pod as a shopping
cart: it holds the item(s), it gets a number, and it can be wheeled to any node.

Pods are **disposable**. They get random names (`python-demo-web-7d9f6b8c4-x2k9p`), they die,
new ones appear. Never get attached to a pod. Never talk to a pod by its IP.

```bash
kubectl -n python-demo get pods -o wide        # see names, status, IPs, nodes
kubectl -n python-demo describe pod <name>     # everything about one pod, incl. events
```

### 2.4 Deployments and ReplicaSets — *"always keep 2 checkout lanes open"*

You almost never create pods by hand. You create a **Deployment** that says: *run this image,
with these settings, and keep **N** copies (replicas) alive*. Behind the scenes it creates a
**ReplicaSet** (the counter that keeps N pods) and, when you change the image, a *new* ReplicaSet,
moving pods over gradually (a **rolling update**) so the store never closes.

Grocery version: the manager's rule "always have 2 checkout lanes open". If a cashier leaves,
another opens a lane. When the new register software arrives, lanes are upgraded one at a time.

```bash
kubectl -n python-demo get deploy,rs
kubectl -n python-demo rollout status deployment/python-demo-web
kubectl -n python-demo rollout history deployment/python-demo-web
kubectl -n python-demo rollout undo deployment/python-demo-web       # go back one version
```

### 2.5 Services — *the store's phone number that never changes*

Pods come and go with new IPs. A **Service** is a stable name and IP that always finds the
current pods behind it, using **labels** (sticky notes on every pod like
`app.kubernetes.io/component=web`). It also **load-balances**: requests take turns across pods.

Every Service gets a DNS name: `<service>.<namespace>.svc.cluster.local`, and inside the same
namespace just `<service>`. That's why `web` calls `http://python-demo-api` — no IPs anywhere.

Three flavours:

| Type | Analogy | When |
|---|---|---|
| `ClusterIP` (default) | the store's *internal* extension number | most services; use `kubectl port-forward` to peek from outside |
| `NodePort` | a side door on every building | rarely; quick tests |
| `LoadBalancer` | the store's public phone number in the phone book | cloud (AKS gives you a public IP) |

```bash
kubectl -n python-demo get svc
kubectl -n python-demo get endpoints python-demo-web    # the pod IPs currently behind it
```

### 2.6 Namespaces — *departments*

A **namespace** is a department: produce, bakery, dairy. Names only need to be unique *within* a
department, resource limits and permissions can be set per department, and `kubectl delete
namespace` clears out the whole department at once. Our app lives in namespace `python-demo`.
Kubernetes' own machinery lives in `kube-system` — don't shop there.

Every `kubectl` command in this tutorial has `-n python-demo`. Forget it and you'll be looking
at the wrong department (the `default` namespace) and see nothing.

### 2.7 ConfigMaps and Secrets — *the notice board and the locked drawer*

Settings must not be baked into the image (then you'd need a new image just to change a greeting).
They are handed to the container as **environment variables** from:

* a **ConfigMap** — the public notice board: `GREETING`, `LOG_LEVEL`, `API_URL`.
* a **Secret** — the manager's locked drawer: `API_TOKEN`. Same mechanism, treated with care
  (Part 7 explains the "care").

In `app.config.yaml`, `services[].config` becomes a ConfigMap and `services[].secrets` lists
which **keys** a service needs — the **values** come from `secrets.env` (laptop) or Key Vault (Azure).

```bash
kubectl -n python-demo get configmap python-demo-api-config -o yaml
kubectl -n python-demo get secret python-demo-api-secrets            # values are hidden
```

### 2.8 Labels and selectors — *sticky notes*

Everything can carry labels (`key=value` sticky notes). Services, Deployments, NetworkPolicies and
you (`kubectl get pods -l app.kubernetes.io/component=api`) *select* things by label. Our chart
uses the standard labels `app.kubernetes.io/name`, `app.kubernetes.io/component`,
`app.kubernetes.io/instance`, `app.kubernetes.io/version`, `app.kubernetes.io/managed-by`.

### 2.9 Health probes — *"are you open?" / "are you okay?"*

Kubernetes asks each container two questions:

* **readiness** (`/health` every 5 s): *Are you ready to take customers?* If no, the Service
  stops sending traffic to that pod, but leaves it alone.
* **liveness** (`/health` every 10 s): *Are you okay?* If it fails repeatedly, the container is
  restarted.

Without probes, a broken pod keeps receiving traffic. Both apps expose `/health` for this.

### 2.10 Resources — *how much shelf space each item may take*

Each container declares **requests** (the space it's guaranteed — used by the scheduler to
choose a node) and **limits** (the most it may ever use — CPU is throttled, memory over the limit
gets the container killed, "OOMKilled"). Ours: request 25m CPU / 32Mi, limit 250m / 128Mi.
(`250m` = 0.25 of one CPU core.) The autoscaler in Part 8 measures usage *against the request*.

### 2.11 YAML manifests — *the paperwork*

Everything above is described in YAML files. `k8s/web.yaml` is a Deployment + Service written by
hand; `helm/python-demo/templates/*.yaml` are the same things written as *templates* that fill in
values from `app.config.yaml`. Every manifest has the same four parts:

```yaml
apiVersion: apps/v1          # which API "form" this is
kind: Deployment             # what kind of thing
metadata:                    # name, namespace, labels
  name: python-demo-web
spec:                        # what you WANT
  ...
```

and Kubernetes adds a fifth, `status`, which is what *is*. `kubectl get ... -o yaml` shows all five.

---

## Part 3 — `kubectl`: the store manager's walkie-talkie

`kubectl` ("cube-control" or "cube-cuddle" — both are fine) is the command-line tool that talks
to the API server. It does **not** run anything itself; it sends requests and prints answers.

### 3.1 The grammar

```
kubectl  <verb>  <noun>  [name]  [-n namespace]  [flags]
kubectl  get     pods              -n python-demo   -o wide
kubectl  describe deployment python-demo-web -n python-demo
```

* **Verbs**: `get` (list), `describe` (details + events), `logs`, `exec`, `apply` (create or
  update from YAML), `delete`, `scale`, `rollout`, `port-forward`, `top`, `explain`.
* **Nouns** (with short names): `pods` (`po`), `deployments` (`deploy`), `services` (`svc`),
  `replicasets` (`rs`), `namespaces` (`ns`), `configmaps` (`cm`), `secrets`, `nodes` (`no`),
  `horizontalpodautoscalers` (`hpa`), `networkpolicies` (`netpol`), `events` (`ev`), `all`.

### 3.2 Which store am I talking to? — contexts

`kubectl` keeps a **kubeconfig** file (`~/.kube/config`) with one **context** per cluster.
kind and AKS each add one. Always check before you delete anything:

```bash
kubectl config current-context           # kind-python-demo  or  aks-python-demo
kubectl config get-contexts
kubectl config use-context kind-python-demo
```

### 3.3 The commands you'll use every day

```bash
# LOOK
kubectl get nodes -o wide
kubectl -n python-demo get all                               # deploy, rs, pods, svc, hpa
kubectl -n python-demo get pods -w                           # -w = watch live
kubectl -n python-demo get pod <pod> -o yaml                 # the full object incl. status
kubectl -n python-demo describe pod <pod>                    # human-readable + EVENTS at the bottom
kubectl -n python-demo get events --sort-by=.metadata.creationTimestamp
kubectl -n python-demo logs deployment/python-demo-api -f    # -f = follow; --previous = crashed container
kubectl -n python-demo top pods                              # CPU/memory (needs metrics-server)

# TOUCH
kubectl -n python-demo exec -it deployment/python-demo-web -- python3 -c "print('hi from inside')"
kubectl -n python-demo port-forward svc/python-demo-web 8080:80
kubectl -n python-demo scale deployment/python-demo-web --replicas=3
kubectl -n python-demo rollout restart deployment/python-demo-api   # rolling restart (after a new image)
kubectl -n python-demo rollout undo deployment/python-demo-api      # roll back
kubectl apply -f k8s/web.yaml                                      # create/update from YAML
kubectl delete -f k8s/web.yaml
kubectl -n python-demo run tester --rm -it --restart=Never --image=curlimages/curl -- curl http://python-demo-api/health

# LEARN
kubectl explain deployment.spec.strategy       # built-in docs for any field
kubectl api-resources                          # every noun the cluster knows
```

### 3.4 `apply` vs `create` — *and what "declarative" means for you*

`kubectl create` fails if the thing exists. `kubectl apply -f file.yaml` says "make reality match
this file" — it creates or updates, and you can run it 100 times. Always use `apply` (and Helm,
which does the same thing with more bookkeeping).

### 3.5 Reading a pod status

| STATUS | Meaning | First thing to do |
|---|---|---|
| `Running` + READY `1/1` | good | — |
| `Running` + READY `0/1` | container runs but readiness probe fails | `logs`, check `/health` |
| `ContainerCreating` | pulling image / mounting volumes | wait; `describe` if > 1 min |
| `ImagePullBackOff` / `ErrImagePull` | image name/tag wrong or not in the registry | Part 5 |
| `CrashLoopBackOff` | the program exits right after starting | `logs --previous` |
| `Pending` | no node has room (or a scheduling rule blocks it) | `describe` → Events |
| `OOMKilled` (in describe) | used more memory than its limit | raise `resources.limits.memory` |

---

## Part 4 — Helm: recipe cards for whole departments

### 4.1 The problem Helm solves

Our tiny app already needs 2 Deployments, 2 Services, 2 ConfigMaps, 1 Secret, 2 HPAs,
3 NetworkPolicies, 2 ServiceAccounts = **14 YAML objects**. Real apps have hundreds, and you
want the same app in *dev*, *test* and *prod* with only a few values different (replicas, image
tag, hostnames). Copy-pasting YAML doesn't scale.

**Helm** is the package manager for Kubernetes:

| Helm word | Meaning | Analogy |
|---|---|---|
| **Chart** | a folder of YAML *templates* + default `values.yaml` | a recipe card for a whole department |
| **Values** | the numbers/strings you plug into the templates | "make 2 lanes, use register software 1.0.0" |
| **Release** | one installed copy of a chart in a namespace, with a name | the bakery department as actually set up on Tuesday |
| **Revision** | every upgrade creates a numbered snapshot you can roll back to | "the way it was set up before Tuesday's change" |

The chart lives in `helm/python-demo/`. Its `templates/deployment.yaml` doesn't say "web" or
"api" anywhere — it *loops* over `services` in the values and stamps out one Deployment each.
That's why adding a service to `app.config.yaml` needs zero YAML edits.

### 4.2 The commands

```bash
helm lint helm/python-demo -f build/helm-values.yaml          # is the chart well-formed?
helm template python-demo helm/python-demo -f build/helm-values.yaml | less    # SHOW me the YAML it would create (no cluster needed)
helm upgrade --install python-demo helm/python-demo \
     -n python-demo --create-namespace \
     -f build/helm-values.yaml -f build/secrets-values.yaml \
     --wait --timeout 3m                                        # install if new, upgrade if exists
helm list -n python-demo                                        # releases in the namespace
helm status python-demo -n python-demo                          # + the NOTES the chart prints
helm get values python-demo -n python-demo                      # what values the release was installed with
helm get manifest python-demo -n python-demo                    # the exact YAML Helm applied
helm history python-demo -n python-demo                         # revisions
helm rollback python-demo 1 -n python-demo                      # back to revision 1
helm test python-demo -n python-demo --logs                     # run the chart's own test pod
helm uninstall python-demo -n python-demo
```

**`helm upgrade --install`** is the one to remember: it's idempotent, like `kubectl apply`.

### 4.3 What's new in Helm 4 (November 2025)

* **Server-side apply** is the default: Kubernetes itself merges changes; fewer surprises when
  something else (an autoscaler, an operator) also edited an object.
* **`--wait` really waits** (kstatus): it returns when every resource is *Ready*, not just created.
  It needs the `watch` permission on the cluster (fine for admins, check RBAC in CI).
* Renamed flags: `--atomic` → `--rollback-on-failure`, `--force` → `--force-replace`.
  Old names still work with a warning; update your scripts.
* Plugins moved to a new system (WASM support), post-renderers are plugins now, OCI digest installs
  (`oci://registry/chart@sha256:...`) for supply-chain safety.
* Charts written for Helm 3 (`apiVersion: v2`) keep working — ours is one.

### 4.4 How values flow in this project

```
app.config.yaml ──(tools/appconfig.py render)──► build/helm-values.yaml ──┐
secrets.env     ──(tools/appconfig.py render)──► build/secrets-values.yaml ─┼──► helm upgrade --install ──► 14 objects
helm/python-demo/values.yaml (chart defaults, e.g. publicServiceType) ────┘
```

Later files win. Azure adds `--set publicServiceType=LoadBalancer` and `global.imageRegistry`.

### 4.5 Helm vs raw kubectl — pros and cons

| | Raw `kubectl apply -f k8s/` | Helm chart |
|---|---|---|
| Learning curve | lowest — the YAML is what runs | templates + values to learn |
| Repeating for dev/test/prod | copy files, edit by hand | one chart, three values files |
| Upgrades & rollback | manual; no history | `helm history` / `rollback` built in |
| Sharing with others | send a folder | publish a versioned chart (OCI registry) |
| Debugging | easy — no indirection | `helm template` shows the output first |
| Best for | learning, one-off objects, tiny apps | anything you deploy more than once |

This repo keeps both: `k8s/` to *read*, the chart to *run*. (Kustomize is a third option: plain
YAML with overlays, no templating — good middle ground, not covered here.)

---

## Part 5 — Why images matter

An image is the *only* thing that moves from your laptop to the cluster to the cloud. If it is
wrong, everything downstream is wrong. Things beginners hit within the first week:

### 5.1 Names, tags and digests

```
demoacr.azurecr.io / python-demo-api : 1.0.0
└── registry ─────┘ └── repository ─┘ └ tag ┘
```

* A **tag** is a *movable* label. `latest` today may be a different image tomorrow. Two people
  running `image: python-demo-api:latest` can get two different programs. **Never deploy `latest`.**
  Use a version (`1.0.0`) or, better, a git SHA (`1.0.0-3f2a9c1`).
* A **digest** (`@sha256:…`) is the fingerprint of the exact bytes. It can't move. Production
  systems and Helm 4's OCI support use digests for exactly this reason.
* Kubernetes's `imagePullPolicy`: `IfNotPresent` (use the copy on the node if there is one —
  fine with unique tags), `Always` (check the registry every time — required if you *do* reuse a
  tag), `Never` (only local). Our default is `IfNotPresent`, which is why after rebuilding with the
  **same** tag you must `kind load` again *and* `rollout restart`.

### 5.2 `ImagePullBackOff` — the #1 beginner error

The node cannot fetch the image. Causes, in order of likelihood:

1. Typo in the name or tag (`kubectl describe pod` → Events shows the exact string it tried).
2. Local image never loaded into kind (`./scripts/03-load-images.sh`).
3. Registry needs a login (AKS: was ACR attached? `az aks update --attach-acr`).
4. Wrong architecture (an `arm64` image on `amd64` nodes) — build with `--platform linux/amd64`.

### 5.3 Reading our Dockerfile line by line

```dockerfile
FROM python:3.13-slim AS build                 # start from a small official base (not "ubuntu" + apt)
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt   # deps in a separate stage/layer

FROM python:3.13-slim                          # runtime stage: no build tools, no pip cache
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PORT=8080
COPY --from=build /install /usr/local          # bring only the installed packages
COPY app.py .                                  # code LAST: it changes most, so earlier layers stay cached
USER 65532:65532                               # never run as root inside a container
EXPOSE 8080                                    # documentation; the real port is in app.config.yaml
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]   # a real server, not flask's dev server
```

**Layers**: each instruction is a layer that is cached and shared. Put things that rarely change
(base, dependencies) first and things that change often (your code) last → rebuilds take seconds
and every version shares the same base layers in the registry.

**Size**: `python:3.13-slim` ≈ 150 MB vs `python:3.13` ≈ 1 GB. Smaller = faster pulls, faster
scaling, fewer things to patch. `alpine` is smaller still but uses `musl`, which can break Python
wheels — `slim` is the safe default.

**Non-root + read-only**: our pods also set `runAsNonRoot`, `readOnlyRootFilesystem`,
`allowPrivilegeEscalation: false`, `capabilities: drop: ALL`, `seccompProfile: RuntimeDefault`.
If an attacker breaks into the app, they land in a locked room with no tools. gunicorn needs
`/tmp`, so the chart mounts a small `emptyDir` there.

**Pin versions** (`flask==3.1.2`) so a build next month produces the same image. Rebuild
regularly anyway to pick up base-image security fixes. Scan images (`docker scout`, `trivy`) in CI.

### 5.4 Where images live per environment

| Environment | Build | Store | Pull |
|---|---|---|---|
| laptop, kind | `docker build` | your Docker daemon | `kind load docker-image` |
| laptop, compose / terraform local-docker | `docker build` | your Docker daemon | direct |
| Azure | `az acr build` (in the cloud) | ACR | AKS pulls with its identity (`--attach-acr`), VM pulls with its managed identity |

---

## Part 6 — Controlling network access

### 6.1 The default is "everyone can talk to everyone"

Out of the box, every pod can reach every other pod in every namespace. In the grocery store
that's "any customer can walk into the stock room and the manager's office". Fine for a demo,
not fine for a real store. The tool that changes it is the **NetworkPolicy**, enforced by the
cluster's network plugin (**CNI**): kind ≥ 0.24 does it out of the box; on AKS we chose **Cilium**.

### 6.2 The two-step pattern: lock every door, then hand out badges

**Step 1 — default deny** (in the chart: `networkPolicy.defaultDeny: true`):

```yaml
kind: NetworkPolicy
metadata: { name: python-demo-default-deny-ingress }
spec:
  podSelector: {}            # applies to EVERY pod in the namespace
  policyTypes: ["Ingress"]   # ... for incoming connections
  # no `ingress:` rules = nothing is allowed in
```

**Step 2 — allow-lists**, generated from `app.config.yaml`:

```yaml
services:
  - name: web
    ports: [{ ..., expose: public }]     # → allow from anywhere (any namespace + any outside IP)
  - name: api
    ports: [{ ..., expose: cluster }]    # → NOT from outside
    network:
      allowFrom: [web]                   # → only pods with web's labels
```

becomes

```yaml
kind: NetworkPolicy
metadata: { name: python-demo-api-allow }
spec:
  podSelector: { matchLabels: { app.kubernetes.io/component: api } }
  ingress:
    - from:
        - podSelector: { matchLabels: { app.kubernetes.io/component: web } }
      ports: [{ port: 8080 }]
```

Policies are **additive**: if *any* policy allows a connection, it's allowed. There is no
"deny" rule; you deny by *not allowing*.

### 6.3 See it work

```bash
./scripts/09-network.sh show     # list + describe the policies
./scripts/09-network.sh test     # web → api: OK.  stranger pod → api: times out after 5 s
./scripts/09-network.sh off      # helm upgrade with networkPolicy.enabled=false → stranger now succeeds
./scripts/09-network.sh on
```

`kubectl port-forward` still reaches `api` even with the policy — it enters through the node's
loopback inside the pod, not over the cluster network. That's a debugging door, not a security hole,
but remember it.

### 6.4 The layers of "who can reach what"

| Layer | Controls | Tool | In this project |
|---|---|---|---|
| Pod ↔ pod | which services may call which | NetworkPolicy | `services[].network.allowFrom`, `expose` |
| Cluster ↔ internet | is a service reachable from outside at all | Service type (`ClusterIP` vs `LoadBalancer`), Ingress | `expose: public` + `publicServiceType` |
| Who from the internet | only your office IP | `loadBalancerSourceRanges` → cloud LB + NSG | `scripts/azure/09-network.sh lock-to-me` |
| VM firewall | ports open on a plain Linux host | `ufw` + Azure NSG | `hosts.exposePorts` |
| Egress | what pods may call *out* (DNS, APIs) | NetworkPolicy `policyTypes: [Egress]`, Cilium FQDN policies | not enabled (exercise: add it) |

School version: the classroom door (pod policy), the school gate (LoadBalancer), the sign-in
desk that only admits listed visitors (source ranges), and the fence (VM firewall).

### 6.5 Best practices

* Start every namespace with a default-deny ingress policy; add allow rules per service.
* Prefer `podSelector` over IP addresses — pods move, labels don't.
* Keep `api`-style services `ClusterIP`; expose *one* front door (`web` or an Ingress).
* Test the *negative* case in CI (a stranger must be blocked) — `05-test.sh` does.
* When you add egress rules, always allow DNS (UDP/TCP 53 to `kube-dns`) first.

---

## Part 7 — Secrets

### 7.1 Config vs secret

A **ConfigMap** is for values you'd happily print on a poster (greeting, log level, the api
URL). A **Secret** is for values that would hurt if printed (tokens, passwords, keys). Both end up
as environment variables in the container; the difference is *how they're handled around it*.

### 7.2 What a Kubernetes Secret really is

```bash
./scripts/08-secrets.sh show
```

You'll see `API_TOKEN: Y2hhbmdlLW1lLWxvY2FsLXRva2Vu`. That is **base64**, an *encoding* anyone can
reverse (`echo Y2hh... | base64 -d`) — **not encryption**. So a Secret protects you only through:

1. **Access control (RBAC)**: most users and all app pods can't read Secrets.
2. **Not in git**: `secrets.env` is git-ignored; `k8s/secret.example.yaml` holds a dummy value.
3. **Encryption at rest**: managed clusters (AKS) encrypt etcd; on your own cluster you enable it.
4. **Not in logs**: the api prints its token *masked* (`************en`). Never `print(token)`.

### 7.3 How the value travels

```
laptop:  secrets.env ──► tools/appconfig.py render secrets ──► build/secrets-values.yaml ──► helm -f ──► Secret ──► env var API_TOKEN
Azure:   az keyvault secret set ──► scripts/azure/08-secrets.sh deploy (reads Key Vault, same path as above)
prod:    Key Vault ──► Secrets Store CSI driver ──► mounted into the pod, synced to a Secret; no laptop involved
```

The chart also adds a `checksum/secret` annotation to the pod template, so **changing a secret
value restarts the pods** automatically — otherwise running containers would keep the old value.

### 7.4 Rotation

```bash
./scripts/08-secrets.sh rotate new-token-123     # writes secrets.env, re-deploys, shows the api's masked token
```

Rotate on a schedule and immediately when someone leaves the team. With Key Vault + CSI driver
(`secret_rotation_enabled`), pods pick up new versions without a redeploy.

### 7.5 Best practices (grocery version: the locked drawer rules)

* One key per secret, named like the env var (`API_TOKEN`), listed in `app.config.yaml` **without a value**.
* Give each service *only* the secrets it declares — `web` has none; it can't read `api`'s.
* Values live in a vault (Azure Key Vault / AWS Secrets Manager / Vault); laptops get short-lived copies.
* Never commit `secrets.env`, `*.tfvars` with secrets, or kubeconfigs. `.gitignore` already covers these.
* Prefer **identities** over passwords: AKS pulls from ACR with its managed identity; the VM logs in to
  ACR with its identity (see `setup/configure.sh`); pods can use *workload identity* to read Key Vault.
* Tools like `git-secrets`/`gitleaks` in CI catch accidental commits.

---

## Part 8 — Scaling and controlling scale

### 8.1 Three dials

| Dial | Analogy | Kubernetes object | Command |
|---|---|---|---|
| **Replicas** (how many pods) | how many checkout lanes are open | Deployment `.spec.replicas` | `kubectl scale`, or `scale.replicas` in the config |
| **Autoscaling pods** | a manager who opens lanes when lines get long | **HorizontalPodAutoscaler** (HPA) | `scale.autoscale` in the config |
| **Autoscaling nodes** | building a new checkout area when the store is full | cluster autoscaler (AKS) | `targets.azure.aks.autoscale` |

There's also *vertical* scaling — giving a pod more CPU/memory (`resources`) — like a bigger lane
instead of more lanes. The Vertical Pod Autoscaler can do that automatically; not used here.

### 8.2 Manual scaling

```bash
./scripts/07-scale.sh manual web 4          # kubectl scale deployment/python-demo-web --replicas=4
kubectl -n python-demo get pods -w
```

If an HPA manages the deployment, it will pull the number back into its `[min, max]` range within
about a minute — the HPA owns the dial. That's why the chart *omits* `replicas` from the
Deployment when autoscaling is enabled: otherwise every `helm upgrade` would reset the count.

### 8.3 The HorizontalPodAutoscaler

From `app.config.yaml`:

```yaml
scale:
  replicas: 1
  autoscale: { enabled: true, minReplicas: 1, maxReplicas: 4, targetCPUUtilizationPercentage: 70 }
```

Every 15 s the HPA reads pod CPU usage from **metrics-server** (the cluster's thermometer —
`01-create-cluster.sh` installs it; AKS has it built in), compares it with the target (**70 % of
the CPU request**, i.e. 70 % of 25m), and computes:

```
desired = ceil( current_replicas × current_usage / target )
```

Scale-up is immediate; scale-down waits a stabilisation window (60 s here, 5 min by default)
so brief lulls don't cause flapping.

### 8.4 Watch it happen

```bash
./scripts/07-scale.sh load 60      # a load pod (wearing web's labels so the policy lets it through)
                                   # hits api /api/work?ms=300 non-stop for 60 s
# in another terminal:
./scripts/07-scale.sh watch        # hpa TARGETS climbs past 70%, REPLICAS 1 → 2 → 3..., then back down
```

If TARGETS shows `<unknown>`, metrics-server isn't running or the pods have no CPU `requests`.

### 8.5 Scaling nodes (Azure)

Pods only scale if there is room. On AKS the **cluster autoscaler** (enabled in
`03-create-aks.sh` with `--enable-cluster-autoscaler --min-count 1 --max-count 3`) adds a VM when
pods are `Pending` for lack of resources and removes idle VMs later.

```bash
./scripts/azure/07-scale.sh status              # node pool min/max/current
./scripts/azure/07-scale.sh autoscaler 1 5      # change the range
./scripts/azure/07-scale.sh nodes 3             # manual (only when the autoscaler is off)
```

### 8.6 Best practices

* **Always set requests** — the scheduler and the HPA are blind without them.
* Set `minReplicas: 2` for anything user-facing so one pod can restart without downtime.
* Keep `maxReplicas` realistic for your node pool; scaling past what nodes can hold just makes `Pending` pods.
* Use a **PodDisruptionBudget** in production so node upgrades don't take all replicas at once.
* Scale on the metric that matters: CPU is the easy default; requests-per-second or queue length
  (via KEDA or custom metrics) is often better.

---

## Part 9 — Phase by phase: every script explained

All scripts share `scripts/lib/common.sh`, which validates `app.config.yaml`, renders `build/`
and loads variables like `$APP_NAME`, `$SERVICES`, `$SERVICE_WEB_IMAGE`. Nothing is hard-coded;
rename the project in the config and every script follows.

### Phase 0 — `00-check-prereqs.sh`: *count the tools before opening the store*
Runs `docker info` (is Docker up?), checks `kind kubectl helm curl python3`, warns if Helm is
< 4, validates the config against `schema/app-config.schema.json` and prints the summary.
**Fails fast** with a clear message instead of failing five minutes later.

### Phase 1 — `01-create-cluster.sh`: *build the store*
`kind create cluster --name python-demo --config kind-config.yaml` makes two Docker containers
(control-plane + worker) and writes a kubeconfig context `kind-python-demo`. Then it installs
**metrics-server** (with `--kubelet-insecure-tls`, because kind's kubelets use self-signed
certificates) so `kubectl top` and the HPA work. Idempotent: re-running skips existing pieces.

Look: `kubectl get nodes -o wide`, `docker ps` (the nodes are containers!), `kubectl -n kube-system get pods`.

### Phase 2 — `02-build-images.sh`: *pack the lunch boxes*
For each service in the config: `docker build --pull -t <app>-<svc>:<version> apps/<svc>`.
`--pull` refreshes the base image. Look: `docker images | grep python-demo`.

### Phase 3 — `03-load-images.sh`: *carry the boxes into the store*
`kind load docker-image <image> --name python-demo` copies each image into every node's
containerd. kind nodes have their **own** image store — your laptop's Docker isn't visible to them.
(On AKS this phase is replaced by pushing to ACR.)

### Phase 4 — `04-deploy-helm.sh`: *hang up the department plan*
Renders `build/helm-values.yaml` (+ `secrets-values.yaml` if `secrets.env` exists), runs
`helm lint`, then `helm upgrade --install python-demo helm/python-demo -n python-demo
--create-namespace -f ... --wait --timeout 3m`. `--wait` returns only when every pod is Ready.
Look: `kubectl -n python-demo get all,hpa,netpol`, `helm status python-demo -n python-demo`.

*Alternative* — `04-deploy-kubectl.sh` applies the hand-written `k8s/*.yaml` with plain kubectl
(building the Secret from `secrets.env` with `kubectl create secret generic --from-env-file`).
Don't run both: same object names. Uninstall the Helm release first.

### Phase 5 — `05-test.sh`: *the inspection*
Port-forwards web→18080 and api→18081, then checks: (1) `/health` of both, (2) api GET and POST,
(3) `/api/config` shows ConfigMap values and the **masked** secret, (4) web `/api-config` proves
web→api works over the cluster DNS name, (5) four calls to web `/config` show different pod
names → load balancing, (6) a throw-away `curlimages/curl` pod tries to reach api and **must
time out** → the NetworkPolicy is enforced. Exit code 0 = all good; use it in CI.

### Phase 6 — `06-port-forward.sh`: *open the front door for you*
`kubectl port-forward svc/python-demo-web 8080:80` for every `expose: public` service, so
localhost:8080 lands in the cluster. Ctrl+C closes it. (Real clusters use a LoadBalancer/Ingress.)

### Phase 7 — `07-scale.sh manual|load|watch` — see Part 8.

### Phase 8 — `08-secrets.sh show|rotate` — see Part 7.

### Phase 9 — `09-network.sh show|test|off|on` — see Part 6.

### Phase 10 — `10-cleanup-apps.sh`: *close the department*
`helm uninstall`, delete leftovers from `k8s/`, delete the namespace. The cluster stays for the next run.

### Phase 99 — `99-destroy.sh`: *demolish the building*
`kind delete cluster --name python-demo`. Docker itself keeps running.

### `run-all.sh`
Phases 0→5 in order, stopping at the first failure (`set -euo pipefail`).

### `new-project-from-template.sh <name> <dir>`
Copies this repo into a new project, renames everything, validates, first commit. See `TEMPLATE.md`.

---

## Part 10 — Where to go next

* **Same app in the cloud** with the Azure CLI — `docs/02-azure-cli-tutorial.md`
  (resource groups, ACR, AKS, managed identities, Key Vault, load balancers, a base Linux VM).
* **Same app as code** with Terraform — `docs/03-terraform-tutorial.md`
  (local Docker, local kind, Azure — all reading the same `app.config.yaml`).
* **Configuring base Linux machines** with scripts, cloud-init and Ansible —
  `docs/05-base-linux-setup-and-ansible.md`.
* **The config schema, field by field** — `docs/04-app-config-schema-reference.md`.
* **Best practices, pros & cons of every choice** — `docs/06-best-practices-and-pros-cons.md`.
* **Cheat sheet** — `docs/07-command-cheatsheet.md`. **When it breaks** — `docs/08-troubleshooting.md`.

### Glossary (one line each)

**API server** the front desk every request goes through · **CNI** the network plugin that gives pods IPs and enforces NetworkPolicy · **ConfigMap** non-secret settings · **container** a running, packaged program · **context** which cluster `kubectl` talks to · **controller** a loop that makes reality match your YAML · **Deployment** "keep N copies of this pod running, update them gradually" · **digest** the unchangeable fingerprint of an image · **etcd** the cluster's record book · **HPA** adds/removes pods based on load · **image** a frozen, read-only snapshot of a container · **Ingress** HTTP routing rules for outside traffic · **kubeconfig** the file with your clusters and credentials · **label** a key=value sticky note · **liveness/readiness** "are you okay?" / "are you open?" · **metrics-server** the thermometer for CPU/memory · **namespace** a department · **NetworkPolicy** rules for who may talk to whom · **node** a computer that runs pods · **pod** the smallest unit Kubernetes runs · **registry** the warehouse for images · **release** an installed Helm chart · **replica** one copy of a pod · **ReplicaSet** the counter that keeps N pods · **Secret** sensitive settings, guarded by RBAC · **Service** a stable name/IP + load balancer in front of pods · **tag** a movable label on an image · **values** the inputs to a Helm chart.
