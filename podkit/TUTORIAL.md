# podkit tutorial — deploying pods to a cluster you already have

This tutorial starts with **one complete example, step by step** (a pod that talks to a
PostgreSQL database, deployed to an existing AWS EKS cluster). After that it explains every
piece, the background you need, the best practices baked in, and the pros and cons of the
choices you can make. You do not need to know Terraform or Ansible to follow along.

---

## Part 1 — Step by step: the PostgreSQL pod on AWS

### What you need before you start

| Thing | Why |
| --- | --- |
| A Kubernetes cluster that already exists (EKS here; AKS and GKE work the same way) | podkit never creates clusters, only pods inside them |
| `kubectl`, `aws` CLI, Python 3.10+ | run the scripts and the generator |
| `terraform` (or `opentofu`) 1.6+ | only if you want the Terraform path or a cloud identity for the pod |
| `docker` | to build the small "command pod" image once |
| A secret named `orders-pg-password` in AWS Secrets Manager | the database password (podkit reads it, never stores it) |

### Step 1 — install the generator

```bash
git clone <this repo> podkit && cd podkit
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

### Step 2 — look at the pod description

Open `examples/pg-client.yaml`. It is the *only* file you write for a pod. The important part:

```yaml
metadata:
  name: pg-client
  namespace: apps
spec:
  provider: aws
  cloud:
    aws: { region: us-east-1, clusterName: demo-eks }   # <- change to YOUR cluster
  image: { repository: postgres, tag: 16-alpine }
  command: ["sleep", "infinity"]                        # stand-in for your app
  scheduling: { spot: true }
  identity: { enabled: true }
  externalServices:
    postgres:
      host: pg.internal.example.com                     # <- change to YOUR database
      database: orders
      user: orders_app
      passwordSecretRef: orders-pg-password             # name in Secrets Manager
      networkCidr: 10.50.0.0/16                         # database subnet
      bootstrapSql: pg-client-bootstrap.sql
  networkPolicy: { enabled: true }
```

Change the four lines marked `<-` to match your cluster and database.

### Step 3 — generate the files

```bash
python -m podgen validate examples/pg-client.yaml
python -m podgen generate examples/pg-client.yaml --provider aws
```

You now have `build/aws/pg-client/`:

```
deploy.sh, destroy.sh, configure.sh   scripts for the kubectl path
k8s/serviceaccount.yaml               the pod's own ServiceAccount
k8s/workload.yaml                     ConfigMap, Deployment, NetworkPolicy
terraform/*.tf                        the same workload as a Terraform root module
ansible/vars.yml, configure.env       inputs for the post-deploy configuration step
bootstrap.sql, pod.env, README.md
```

Open `k8s/workload.yaml` and read it. Everything in it came from the 30 lines above:
resource requests and limits, a spot node selector, `PGHOST`/`PGUSER`/... environment
variables, `PGPASSWORD` from a Secret, a locked-down security context, and a NetworkPolicy
that allows DNS, HTTPS to cloud APIs, and port 5432 to `10.50.0.0/16` — nothing else.

### Step 4 — point kubectl at your cluster

```bash
scripts/cluster-login.sh -p aws -c demo-eks -r us-east-1
kubectl get nodes        # should list your nodes
```

### Step 5 — build and deploy the command pod (once per cluster)

The command pod is a tiny pod that runs the configuration steps *inside* the cluster.

```bash
docker build -t ghcr.io/your-org/podkit-command-pod:latest -f command-pod/Dockerfile .
docker push ghcr.io/your-org/podkit-command-pod:latest
export COMMAND_POD_IMAGE=ghcr.io/your-org/podkit-command-pod:latest
TARGET_NAMESPACES=apps scripts/command-pod.sh deploy
```

### Step 6 — give the pod a cloud identity (Terraform, optional but recommended)

The pod itself does not need cloud permissions in this example (the deploy script reads the
secret for it), so you can skip this step. If your app will call AWS APIs, run:

```bash
scripts/deploy.sh -m terraform build/aws/pg-client      # creates the IAM role + deploys
```

or, to use kubectl for the deploy and Terraform only for the role, copy the `identity` output
into `build/aws/pg-client/pod.env` as `IDENTITY_ID=arn:aws:iam::...`.

### Step 7 — deploy

```bash
scripts/deploy.sh build/aws/pg-client
```

What happens, in order:

1. the `apps` namespace is created if missing;
2. `orders-pg-password` is read from Secrets Manager and written to Secret `pg-client-env`;
3. the ServiceAccount is applied (and annotated with `IDENTITY_ID` if you set it);
4. the Deployment, ConfigMap and NetworkPolicy are applied with server-side apply;
5. the script waits for the rollout;
6. the **post-deploy step** runs in the command pod: it checks the database is reachable,
   runs `bootstrap.sql` (creates the `orders` table if it does not exist) and copies a
   `/tmp/database.conf` into the running pod.

### Step 8 — check, then clean up

```bash
kubectl -n apps get pods,networkpolicy
kubectl -n apps exec deploy/pg-client -- sh -c 'psql -c "\dt"'   # PG* env vars are set
scripts/command-pod.sh scale 0                                   # idle = free
scripts/destroy.sh build/aws/pg-client                           # when you are done
```

To deploy the same pod to Azure or GCP, change nothing but the flag:
`python -m podgen generate examples/pg-client.yaml --provider gcp`.

---

## Part 2 — Background: what all of this is

### Kubernetes in three sentences

A **cluster** is a group of machines (nodes) managed as one computer. A **pod** is the
smallest thing you run on it: one or more containers that share a network address. A
**Deployment** tells Kubernetes "keep N copies of this pod running and replace them one at a
time when I change something" — that is what podkit creates for you.

### The managed clusters: EKS, AKS, GKE

AWS (EKS), Azure (AKS) and Google Cloud (GKE) all run standard Kubernetes, so the pod YAML is
the same everywhere. What differs is *around* the cluster:

| | AWS EKS | Azure AKS | Google GKE |
| --- | --- | --- | --- |
| Log in | `aws eks update-kubeconfig` | `az aks get-credentials` (+ `kubelogin`) | `gcloud container clusters get-credentials` |
| Secret store | Secrets Manager | Key Vault | Secret Manager |
| Pod identity | IRSA or EKS Pod Identity | Workload Identity (federated managed identity) | Workload Identity Federation for GKE |
| Cheap capacity | Spot node groups (`capacityType=SPOT`) | Spot node pools | Spot VMs |

podkit hides those differences behind `spec.provider` and `spec.cloud`.

### Two ways to deploy: kubectl scripts or Terraform

Both paths create exactly the same objects; pick one per pod.

| | kubectl path (`deploy.sh`) | Terraform path (`deploy.sh -m terraform`) |
| --- | --- | --- |
| Pros | nothing to install but kubectl; readable YAML; fast; easy to debug | tracks state, shows a plan before changing anything, also creates the cloud identity and IAM permissions |
| Cons | no plan/diff; cloud identity must come from somewhere else | needs Terraform and a state backend; secret values end up in the state file |
| Best for | day-to-day deploys, CI pipelines, learning | teams already on Terraform, pods that need cloud permissions |

Tip: use Terraform once for the identity, and kubectl for everyday deploys — `pod.env` glues
them together through `IDENTITY_ID`.

### The command pod

Configuration steps (create a keystore, run SQL, copy a file into a pod) need tools —
`openssl`, `keytool`, `psql`, `ansible` — and network access to the database and the API
server. Instead of installing all of that on every laptop and CI runner, podkit runs the steps
inside a small **command pod** (`sleep infinity` + the tools). `scripts/configure.sh` copies the
playbooks and your build folder into it and runs the step there. It gets only *namespaced*
permissions (Role + RoleBinding per namespace you allow) and scales to zero when idle.

You can still run steps from your machine with `CONFIGURE_VIA=local` if you have the tools.

### Ansible or shell?

Every built-in step exists twice: an Ansible playbook and a plain shell script that do the same
thing. `configure.method` picks one.

| | Ansible (`method: ansible`) | Shell (`method: shell`) |
| --- | --- | --- |
| Pros | declarative, idempotent modules, readable task list, good for long flows | zero learning curve, easy to step through, fastest to start |
| Cons | needs Python + collections in the image; slower start | you write the "did it already happen?" logic yourself |
| Best for | multi-step flows, teams that already use Ansible | small one-off jobs, quick fixes |

Override any input at run time: `build/aws/java-server/configure.sh -e rotate=true` (Ansible) or
`build/aws/java-client/configure.sh ROTATE=true` (shell).

### Pre-deploy vs post-deploy

`configure.phase: pre` runs **before** the workload is applied — use it when the pod cannot
start without something (a keystore Secret). `post` runs **after** the rollout is ready — use
it to verify, migrate or push runtime files. podkit picks the right default for its built-in
flows (`tls` → pre, `postgres` → post).

---

## Part 3 — The PodConfig file, section by section

| Section | What it controls | Default |
| --- | --- | --- |
| `metadata.name/namespace` | names of every object | namespace `default` |
| `spec.provider`, `spec.cloud.*` | which cloud, how to find the cluster; keep all three blocks and switch with `--provider` | — |
| `image`, `command`, `args` | the container | `pullPolicy: IfNotPresent` |
| `replicas`, `autoscaling` | how many pods; HPA on CPU when enabled | 1 |
| `resources` | requests and limits (always set) | 100m/128Mi – 500m/256Mi |
| `scheduling.spot` | run on spot/preemptible nodes (adds the cloud's selector + toleration) | false |
| `ports`, `service`, `probe` | networking and health checks | `ClusterIP`, no probe |
| `env`, `secrets`, `files`, `mounts` | plain env, secret env (cloud store or existing Secret), small config files, extra Secret/ConfigMap mounts | — |
| `identity` | cloud identity for the pod + extra IAM policies/roles | disabled |
| `securityContext` | non-root, read-only root filesystem, user/group ids | non-root off (set it on!) |
| `networkPolicy` | default-deny with allow rules: DNS, HTTPS, CIDRs, pods | disabled |
| `externalServices.postgres` | the PostgreSQL flow (env, secret, egress, post-deploy step) | — |
| `tls` | the Java keystore mTLS flow (secrets, mounts, env, pre-deploy step) | — |
| `configure` | `method`, `phase`, custom `playbook`/`script`, extra `vars` | derived |

Run `python -m podgen schema` to print the full JSON Schema with every description.

---

## Part 4 — The second example: pod-to-pod TLS with Java keystores

**mTLS** (mutual TLS) means *both* sides show a certificate: the server proves who it is and the
client must too, so only your own pods can talk to the server. Java programs read certificates
from a **keystore** (your own key + certificate) and a **truststore** (the certificates you
trust). podkit builds both for you.

```bash
docker build -t ghcr.io/acme/java-mtls:1.0.0 examples/java-mtls && docker push ghcr.io/acme/java-mtls:1.0.0
python -m podgen generate examples/java-server.yaml examples/java-client.yaml --provider aws
scripts/deploy.sh build/aws/java-server     # pre-deploy: CA + server keystore + shared truststore
scripts/deploy.sh build/aws/java-client     # pre-deploy: client keystore (same CA, shell variant)
kubectl -n apps logs deploy/java-client     # 200 hello CN=java-client from java-server-...
```

What the pre-deploy step does (`ansible/playbooks/java-keystore.yml` or `configure/java-keystore.sh`):

1. creates a CA once per namespace (Secret `podkit-mtls-ca`, EC P-256, self-signed);
2. issues a certificate for the pod — servers get the Service DNS names as SANs and
   `serverAuth`+`clientAuth`; clients get `clientAuth` only;
3. wraps key + certificate into `keystore.jks` (PKCS12 → JKS with `keytool`) and stores it
   with a random password in Secret `<name>-keystore`;
4. builds the shared `truststore.jks` from the CA (Secret `podkit-mtls-truststore`);
5. restarts running pods that use the keystore so they pick up the new certificate.

The pod sees `KEYSTORE_PATH`, `TRUSTSTORE_PATH`, `KEYSTORE_PASSWORD`, `TRUSTSTORE_PASSWORD`;
`examples/java-mtls/Server.java` and `Client.java` show the ten lines of Java that use them.
Rotate a certificate with `configure.sh -e rotate=true`; rotate the CA by deleting
`podkit-mtls-ca` and rotating every pod.

JKS or PKCS12? Since Java 9 the default keystore format is PKCS12 and JKS is considered legacy,
but every Java version still reads JKS and many apps expect it, so podkit produces JKS. Change
`-deststoretype` in the playbook/script to `PKCS12` if your app prefers it — the Java code does
not change (`KeyStore.getInstance("JKS")` reads both).

---

## Part 5 — Best practices podkit applies for you (and why)

| Practice | Why it matters |
| --- | --- |
| **Requests and limits on every container** | the scheduler packs nodes properly and one pod cannot starve the others; it is also the first lever for cost |
| **Spot capacity with one flag** | 60–90 % cheaper for stateless or batch work; podkit adds the right selector and toleration per cloud |
| **`ClusterIP` by default** | a `LoadBalancer` Service costs money per hour; share one ingress instead |
| **Secrets pulled from the cloud store at deploy time** | nothing secret in git or in generated files; rotation = redeploy (pods restart automatically through a checksum annotation) |
| **One ServiceAccount per pod, no automounted token** | least privilege; the cloud identity is bound to that ServiceAccount only |
| **Non-root, no capabilities, seccomp `RuntimeDefault`, no privilege escalation** | Pod Security "restricted" baseline; turn on `readOnlyRootFilesystem` when the app allows it |
| **Default-deny NetworkPolicy with explicit allows** | a compromised pod cannot roam the cluster or the internet |
| **Rolling updates with `maxUnavailable: 0`, `revisionHistoryLimit: 2`** | zero-downtime deploys without keeping old ReplicaSets around |
| **Command pod is tiny, namespaced, scale-to-zero** | 50 mCPU / 128 MiB while it works, nothing when idle, no cluster-admin |
| **Server-side apply with a field manager** | safe repeated deploys, no fights with other tools |
| **Idempotent configuration steps** | run them twice, get the same result; `rotate=true` when you want change |
| **Pinned provider version ranges** | `kubernetes >= 2.30, < 4.0`, `aws >= 5.40, < 7.0`, `azurerm >= 4.0, < 5.0`, `google >= 6.0, < 8.0` |

Things podkit does **not** do on purpose (keep it simple): no operators or CRDs, no service
mesh, no Helm. If you later need automatic secret sync, add External Secrets Operator or the
Secrets Store CSI driver; if you need certificate management at scale, add cert-manager. The
PodConfig stays the same.

---

## Part 6 — Requirements and gotchas per cloud

**AWS EKS**
* IRSA needs the cluster's OIDC provider registered in IAM (`eksctl utils associate-iam-oidc-provider`); Pod Identity needs the `eks-pod-identity-agent` add-on. Choose with `spec.cloud.aws.identityMode`.
* NetworkPolicy needs it enabled on the VPC CNI (`enableNetworkPolicy: true`) or a CNI such as Calico/Cilium.
* Spot: managed node groups label spot nodes `eks.amazonaws.com/capacityType=SPOT`; with Karpenter use `karpenter.sh/capacity-type=spot` via `scheduling.nodeSelector`.

**Azure AKS**
* Workload Identity needs `--enable-oidc-issuer --enable-workload-identity` on the cluster. The Key Vault must use the RBAC permission model (the module assigns "Key Vault Secrets User").
* Entra-ID-only clusters: the Terraform `kubernetes` provider block needs the `kubelogin` exec snippet shown in the generated `providers.tf`.
* NetworkPolicy needs Azure NPM or Cilium (`--network-policy azure|cilium`).

**Google GKE**
* Workload Identity Federation must be enabled on the cluster and node pool; the module creates the Google service account and the `iam.workloadIdentityUser` binding.
* NetworkPolicy needs Dataplane V2 or Calico enforcement enabled.
* Secret Manager and Secret Manager API must be enabled in the project.

**Everywhere**
* The command pod must be able to reach your database for the PostgreSQL post-deploy step (allow the `ops` namespace in your firewalls, or run the step with `CONFIGURE_VIA=local`).
* `kubectl cp` / `k8s_cp` need `tar` inside the target image.
* Terraform state contains the secret values it read: use the encrypted remote backend from `backend.tf.example`.

---

## Part 7 — Cheat sheet

```bash
python -m podgen validate CONFIG...                              # check
python -m podgen generate CONFIG... --provider aws|azure|gcp|all # generate build/<cloud>/<name>
scripts/cluster-login.sh -p <cloud> ...                          # kubeconfig
scripts/command-pod.sh deploy|ensure|status|shell|scale N|destroy
scripts/deploy.sh [-m terraform] [-y] build/<cloud>/<name>
build/<cloud>/<name>/configure.sh [-e key=value | KEY=VALUE]     # rerun the configuration step
scripts/destroy.sh [-m terraform] [-y] build/<cloud>/<name>
make test                                                        # pytest: every example, every cloud
```
