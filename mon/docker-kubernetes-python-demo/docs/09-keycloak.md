# Keycloak: 2+ Replicas, Exposed on Port 80

*Keycloak is an open-source identity server (logins, SSO, OAuth2/OIDC). This adds it to the
cluster the way the tutorial taught: at least 2 replicas always running, spread across nodes,
a shared database, an autoscaler, a disruption budget, default-deny network policies and one
exposed port. Keycloak 26.7 (August 2026), Postgres 17.*

## Step by step

```bash
./scripts/keycloak.sh deploy        # ≈ 2–3 minutes on kind (first start builds the server)
./scripts/keycloak.sh admin         # the generated admin username/password
./scripts/keycloak.sh open          # kind: http://localhost:8080/admin   (AKS: `status` prints the public IP)
./scripts/keycloak.sh status
./scripts/keycloak.sh destroy       # removes the namespace and the database volume
```

On **AKS** the `keycloak` Service becomes `type: LoadBalancer` → public IP on **port 80**.
On **kind** it becomes `type: NodePort 30080` (reachable from the node containers) and `open`
port-forwards it to your laptop. To reach the NodePort directly from your browser instead,
create the kind cluster with a port mapping (see the comment in `kind-config.yaml`).
Force either mode with `USE_LB=true|false ./scripts/keycloak.sh deploy`.

## What gets created (`k8s/keycloak/`)

| Object | File | Why |
|---|---|---|
| Namespace `keycloak` (Pod Security *baseline*) | `00-namespace.yaml` | its own department, its own policies |
| Secrets `keycloak-admin`, `keycloak-db` | created by the script with random passwords (`01-secrets.example.yaml` shows the shape) | never in git |
| StatefulSet `keycloak-db` (Postgres 17) + headless Service + 2 Gi PVC | `10-postgres.yaml` | **two Keycloak replicas must share one database**; the dev-mode embedded DB would give each pod its own users |
| Deployment `keycloak`, `replicas: 2`, `maxUnavailable: 0`, topology spread across nodes | `20-keycloak.yaml` | at least 2 running, even during rolling updates |
| Service `keycloak` port **80 → 8080** | `20-keycloak.yaml` | the exposed port (type patched by the script) |
| Service `keycloak-headless` port 7800 | `20-keycloak.yaml` | replicas find each other by DNS (JGroups `DNS_PING`) and share the Infinispan cache — sessions survive a pod loss |
| HorizontalPodAutoscaler `minReplicas: 2`, max 4, 75 % CPU | `20-keycloak.yaml` | the "min 2" is enforced even if someone `kubectl scale`s down |
| PodDisruptionBudget `minAvailable: 1` | `20-keycloak.yaml` | node drains/upgrades take one replica at a time |
| NetworkPolicies: default deny; 8080 from anywhere; 7800 only between replicas; 5432 only from Keycloak; 9000 from `kube-system` | `30-network-policy.yaml` | same lock-then-badge pattern as the demo app |

Key Keycloak settings (all environment variables, see the Deployment):

| Variable | Value | Meaning |
|---|---|---|
| `args: ["start"]` | production mode | `start-dev` is for laptops only — no clustering, embedded DB |
| `KC_DB` / `KC_DB_URL` | `postgres` / `jdbc:postgresql://keycloak-db-0.keycloak-db:5432/keycloak` | shared DB via the StatefulSet's stable DNS name |
| `KC_HTTP_ENABLED=true`, `KC_HOSTNAME_STRICT=false`, `KC_PROXY_HEADERS=xforwarded` | HTTP behind a load balancer/port-forward | TLS terminates in front (add an Ingress + cert-manager for HTTPS and set `KC_HOSTNAME=https://sso.example.com`) |
| `KC_HEALTH_ENABLED=true`, `KC_METRICS_ENABLED=true` | `/health/*` and `/metrics` on management port **9000** | probes: startup `/health/started` (up to 5 min), readiness `/health/ready`, liveness `/health/live` |
| `KC_CACHE=ispn`, `KC_CACHE_STACK=kubernetes`, `-Djgroups.dns.query=keycloak-headless.keycloak.svc.cluster.local` | cluster the replicas | without this each replica would keep its own sessions |
| `KC_BOOTSTRAP_ADMIN_*` | from the `keycloak-admin` Secret | first-start admin; create a permanent admin in the console and remove the bootstrap one |

Resources: requests 300 m CPU / 768 Mi, limits 1 CPU / 1.5 Gi per replica — Keycloak is a JVM;
two replicas plus Postgres need ~2 GB free in the cluster (fine on kind with Docker ≥ 4 GB and
on two B2ms AKS nodes).

## Watch the "min 2" rules work

```bash
kubectl -n keycloak get pods -o wide                       # 2 keycloak pods on different nodes (kind: 1 worker → same node)
kubectl -n keycloak delete pod -l app.kubernetes.io/component=server --wait=false; kubectl -n keycloak get pods -w   # replaced immediately
kubectl -n keycloak scale deploy/keycloak --replicas=1     # the HPA raises it back to 2 within a minute
kubectl -n keycloak get hpa -w
kubectl -n keycloak logs deploy/keycloak | grep -i "cluster\|members"   # ISPN view with 2 members
kubectl -n keycloak run t --rm -it --restart=Never --image=curlimages/curl -- curl -m5 keycloak-db-0.keycloak-db:5432   # blocked by policy
```

## Best practices and next steps

* **HTTPS + hostname**: put an Ingress (or Application Gateway for Containers on AKS) in front with a
  certificate, then set `KC_HOSTNAME=https://sso.example.com` and `KC_HOSTNAME_STRICT=true`.
* **Managed database** on Azure: swap the StatefulSet for Azure Database for PostgreSQL Flexible
  Server; point `KC_DB_URL` at it and put the password in Key Vault (CSI driver, see tutorial 02).
* **Optimized image**: for faster, deterministic starts build your own image with
  `kc.sh build --db=postgres …` and run `start --optimized` (see the Keycloak container guide).
* **Operator**: for production the Keycloak Operator (CRD `Keycloak`) manages all of the above
  including rolling upgrades; these manifests show what it does underneath.
* **Realm import**: mount realm JSON at `/opt/keycloak/data/import` and add `--import-realm` to `args`.
* **Backups**: Postgres PVC snapshots or `pg_dump` CronJob; Keycloak itself is stateless apart from the DB.
* **Sizing**: see "Keycloak Performance Benchmarks (26.4)" on keycloak.org — roughly 1 vCPU per 300 logins/s.
